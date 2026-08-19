module WarpEngine
  # The device authorization grant, from both ends.
  #
  # The client's end is #request, #poll and #revoke, all reachable over /api/auth/*.
  # The person's end is #approve and #deny, which the *host* calls from its own page —
  # approving needs a session and a logged-in human, and the engine has neither.
  class DeviceGrantService
    class NotConfigured < StandardError; end
    class UnknownCode < StandardError; end

    # A client asks for a code pair. Deliberately unauthenticated: there is nobody to
    # authenticate as yet, which is the whole reason this flow exists.
    def request(client_name:)
      ensure_configured!

      WarpEngine::DeviceGrant.create!(client_name: client_name.presence&.truncate(128))
    end

    # The client polls with the device code. Returns [state, token], where the token is
    # the plain string and is available exactly once — on the poll that finds the grant
    # newly approved. A second poll gets :approved with no token, which is the honest
    # answer: the secret was handed over and is not kept.
    def poll(device_code:)
      ensure_configured!

      grant = WarpEngine::DeviceGrant.find_by(device_code: device_code.to_s)
      raise UnknownCode if grant.nil?

      return [ grant.state, nil ] unless grant.state == :approved

      # Read once, then gone: the column exists only to carry the secret across the gap
      # between the browser that approved it and the client that is polling for it.
      plain = grant.issued_token
      grant.update_columns(issued_token: nil) if plain.present?
      [ :approved, plain ]
    end

    # The host's approval page calls this with the code a person typed and the subject
    # they are signed in as. Issuing the token here rather than on the next poll keeps
    # the decision and its consequence in one transaction.
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

    def deny(user_code:)
      ensure_configured!

      grant = WarpEngine::DeviceGrant.find_pending_by_user_code(user_code)
      raise UnknownCode if grant.nil?

      grant.update!(denied_at: Time.current)
      grant
    end

    # Signing out: the client throws its own token away. Revocation is a soft delete on
    # the token, so the audit trail of who signed in from where survives it.
    def revoke(token:)
      return false if token.nil?

      token.revoke!
      true
    end

    # Where a person goes to type the user code. A path is made absolute against the
    # request's own base, so a host that configured "/devices" does not have to know its
    # own hostname.
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
