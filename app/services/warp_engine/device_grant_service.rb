module WarpEngine
  # The device authorization flow: a client asks for a grant, the user approves
  # its code in the browser, and the client polls until it receives a catalog
  # WarpEngine::ApplicationToken. Every step but #revoke and #verification_url
  # needs the identity integration (<tt>WarpEngine.identity_configured?</tt>).
  class DeviceGrantService
    # Raised when the identity integration is not configured.
    class NotConfigured < StandardError; end
    # Raised when no grant (or no pending grant) matches the code given.
    class UnknownCode < StandardError; end

    # Creates a pending WarpEngine::DeviceGrant for the client +client_name+
    # (truncated to 128 characters, blank allowed). Returns the grant. Raises
    # NotConfigured.
    def request(client_name:)
      ensure_configured!

      WarpEngine::DeviceGrant.create!(client_name: client_name.presence&.truncate(128))
    end

    # Reports the state of the grant +device_code+.
    #
    # Returns <tt>[state, nil]</tt> while the grant is <tt>:pending</tt>,
    # <tt>:denied</tt> or <tt>:expired</tt>, and <tt>[:approved, token]</tt> once
    # approved. The plain token is handed out once: it is cleared from the grant
    # on this call, so later polls return <tt>[:approved, nil]</tt>. Raises
    # UnknownCode and NotConfigured.
    def poll(device_code:)
      ensure_configured!

      grant = WarpEngine::DeviceGrant.find_by(device_code: device_code.to_s)
      raise UnknownCode if grant.nil?

      return [ grant.state, nil ] unless grant.state == :approved

      plain = grant.issued_token
      grant.update_columns(issued_token: nil) if plain.present?
      [ :approved, plain ]
    end

    # Approves the pending grant +user_code+ for +subject+ (an instance of
    # <tt>WarpEngine.config.access_token_owner_class</tt>): in one transaction it
    # creates a catalog-scoped WarpEngine::ApplicationToken owned by the subject,
    # named after the client, and stores it on the grant for the next #poll.
    # Returns the grant. Raises UnknownCode and NotConfigured.
    def approve(user_code:, subject:)
      ensure_configured!

      grant = WarpEngine::DeviceGrant.find_pending_by_user_code(user_code)
      raise UnknownCode if grant.nil?

      ActiveRecord::Base.transaction do
        token = WarpEngine::ApplicationToken.create!(
          name: grant.client_name.presence || "Client",
          owner_type: WarpEngine.config.access_token_owner_class,
          owner_id: subject.id,
          scopes: [ WarpEngine::ApplicationToken::CATALOG_SCOPE ]
        )
        grant.update!(
          subject_type: WarpEngine.config.access_token_owner_class,
          subject_id: subject.id,
          application_token: token,
          issued_token: token.plain_token,
          approved_at: Time.current
        )
      end

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

    private

    def ensure_configured!
      raise NotConfigured unless WarpEngine.identity_configured?
    end
  end
end
