module WarpEngine

  class DeviceGrantService
    class NotConfigured < StandardError; end
    class UnknownCode < StandardError; end

    def request(client_name:)
      ensure_configured!

      WarpEngine::DeviceGrant.create!(client_name: client_name.presence&.truncate(128))
    end

    def poll(device_code:)
      ensure_configured!

      grant = WarpEngine::DeviceGrant.find_by(device_code: device_code.to_s)
      raise UnknownCode if grant.nil?

      return [ grant.state, nil ] unless grant.state == :approved

      plain = grant.issued_token
      grant.update_columns(issued_token: nil) if plain.present?
      [ :approved, plain ]
    end

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

    def revoke(token:)
      return false if token.nil?

      token.revoke!
      true
    end

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
