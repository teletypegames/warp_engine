module WarpEngine
  # The device authorization flow: a client asks for a grant, the user approves
  # its code in the browser, and the client polls until it receives a
  # WarpEngine::ApplicationToken.
  #
  # A catalog client's grant needs the identity integration
  # (<tt>WarpEngine.identity_configured?</tt>) and yields a catalog token owned
  # by the person. A tool's grant (one asking for Admin API +scopes+, e.g. an
  # editor extension) needs the Admin API, is approved by an administrator in
  # the admin, and yields a token with those scopes owned by the administrator.
  class DeviceGrantService
    # Raised when the identity integration (or, for a tool, the Admin API) is
    # not configured.
    class NotConfigured < WarpEngine::Error; end
    # Raised when no grant (or no pending grant) matches the code given.
    class UnknownCode < WarpEngine::Error; end
    # Raised when a grant asks for scopes that are not Admin API scopes.
    class InvalidScopes < WarpEngine::Error; end

    # Creates a pending WarpEngine::DeviceGrant for the client +client_name+
    # (truncated to 128 characters, blank allowed).
    #
    # [scopes] Admin API scopes (WarpEngine::AdminApi::Scopes::ALL) a tool asks
    #          for; blank for a catalog client
    #
    # Returns the grant. Raises InvalidScopes for a scope outside the Admin API
    # ones, and NotConfigured.
    def request(client_name:, scopes: nil)
      scopes = Array(scopes).map(&:to_s).compact_blank.uniq
      unknown = scopes - WarpEngine::AdminApi::Scopes::ALL
      raise InvalidScopes, "unknown scopes: #{unknown.join(', ')}" if unknown.any?

      scopes.any? ? ensure_tools_configured! : ensure_configured!
      WarpEngine::DeviceGrant.create!(client_name: client_name.presence&.truncate(128), scopes: scopes.presence)
    end

    # Reports the state of the grant +device_code+.
    #
    # Returns <tt>[state, nil]</tt> while the grant is <tt>:pending</tt>,
    # <tt>:denied</tt> or <tt>:expired</tt>, and <tt>[:approved, token]</tt> once
    # approved. The plain token is handed out once: it is cleared from the grant
    # on this call, so later polls return <tt>[:approved, nil]</tt>. Raises
    # UnknownCode and NotConfigured.
    def poll(device_code:)
      grant = WarpEngine::DeviceGrant.find_by(device_code: device_code.to_s)
      grant&.tool? ? ensure_tools_configured! : ensure_configured!
      raise UnknownCode if grant.nil?

      return [ grant.state, nil ] unless grant.state == :approved

      plain = grant.issued_token
      grant.update_columns(issued_token: nil) if plain.present?
      [ :approved, plain ]
    end

    # Approves the pending catalog grant +user_code+ for +subject+ (an
    # instance of <tt>WarpEngine.config.access_token_owner_class</tt>): in one
    # transaction it creates a catalog-scoped WarpEngine::ApplicationToken owned
    # by the subject, named after the client, and stores it on the grant for
    # the next #poll. Returns the grant. Raises UnknownCode (also for a tool's
    # grant) and NotConfigured.
    def approve(user_code:, subject:)
      ensure_configured!

      grant = WarpEngine::DeviceGrant.find_pending_by_user_code(user_code)
      raise UnknownCode if grant.nil? || grant.tool?

      issue(grant, owner_type: WarpEngine.config.access_token_owner_class, subject: subject,
                   scopes: [ WarpEngine::ApplicationToken::CATALOG_SCOPE ])
    end

    # Approves the pending tool grant +user_code+ for the administrator
    # +admin+ (an instance of the Admin API token owner class): the token gets
    # the scopes the grant asked for, and +sync:pair+ while anyone may pair
    # (WarpEngine::Sync::Inbound#pairing_open?), and is owned by +admin+.
    # Returns the grant. Raises UnknownCode (also for a catalog client's
    # grant) and NotConfigured.
    def approve_tool(user_code:, admin:)
      ensure_tools_configured!

      grant = find_pending_tool(user_code)
      scopes = Array(grant.scopes)
      scopes |= [ WarpEngine::AdminApi::Scopes::PAIR ] if WarpEngine::Sync.config.inbound.pairing_open?
      issue(grant, owner_type: WarpEngine.config.admin_api.owner_class_name, subject: admin, scopes: scopes)
    end

    # Returns the pending tool grant +user_code+. Raises UnknownCode when there
    # is none.
    def find_pending_tool(user_code)
      grant = WarpEngine::DeviceGrant.find_pending_by_user_code(user_code)
      raise UnknownCode if grant.nil? || !grant.tool?

      grant
    end

    # Marks the pending tool grant +user_code+ denied. Returns the grant.
    # Raises UnknownCode.
    def deny_tool(user_code:)
      grant = find_pending_tool(user_code)
      grant.update!(denied_at: Time.current)
      grant
    end

    # Marks the pending grant +user_code+ denied. Returns the grant. Raises
    # UnknownCode and NotConfigured.
    def deny(user_code:)
      ensure_configured!

      grant = WarpEngine::DeviceGrant.find_pending_by_user_code(user_code)
      raise UnknownCode if grant.nil?

      grant.update!(denied_at: Time.current)
      grant
    end

    # Revokes (soft-deletes) the WarpEngine::ApplicationToken +token+. Returns
    # +false+ when +token+ is +nil+, +true+ otherwise.
    def revoke(token:)
      return false if token.nil?

      token.revoke!
      true
    end

    # The URL where the user approves a code:
    # <tt>WarpEngine.config.identity_verification_url</tt>, or <tt>/devices</tt> by
    # default. A relative path is joined to +base_url+ when one is given.
    def verification_url(base_url: nil)
      configured = WarpEngine.config.identity_verification_url.presence || "/devices"
      return configured if configured.start_with?("http://", "https://")
      return configured if base_url.blank?

      "#{base_url.to_s.chomp('/')}/#{configured.delete_prefix('/')}"
    end

    # The URL where an administrator approves a tool's code:
    # <tt>WarpEngine.config.tool_verification_url</tt>, or the admin's tool
    # sign-in page (<tt>/admin/tool_sign_in</tt>) by default; joined to
    # +base_url+ like #verification_url.
    def tool_verification_url(base_url: nil)
      configured = WarpEngine.config.tool_verification_url.presence || "/admin/tool_sign_in"
      return configured if configured.start_with?("http://", "https://")
      return configured if base_url.blank?

      "#{base_url.to_s.chomp('/')}/#{configured.delete_prefix('/')}"
    end

    private

    def issue(grant, owner_type:, subject:, scopes:)
      ActiveRecord::Base.transaction do
        token = WarpEngine::ApplicationToken.create!(name: grant.client_name.presence || "Client",
                                                     owner_type: owner_type, owner_id: subject.id, scopes: scopes)
        grant.update!(subject_type: owner_type, subject_id: subject.id, application_token: token,
                      issued_token: token.plain_token, approved_at: Time.current)
      end
      grant
    end

    def ensure_configured!
      raise NotConfigured unless WarpEngine.identity_configured?
    end

    def ensure_tools_configured!
      raise NotConfigured unless WarpEngine.config.admin_api.enabled? && WarpEngine.config.admin_api.owner_class_name.present?
    end
  end
end
