module WarpEngine
  # Token authentication for the publishing (/build/*) endpoints.
  # The auth source is exclusive: in :database mode the shared secret is not
  # accepted, in :env mode DB tokens are not.
  module UpdateAuthentication
    extend ActiveSupport::Concern

    private

    attr_reader :current_application_token

    # The token is accepted from the X-Update-Secret header only — in the URL
    # it would leak into proxy and access logs.
    def update_authorized?(required_scope:)
      token = request.headers["X-Update-Secret"].presence
      return false if token.blank?

      case WarpEngine.config.application_token_source
      when :database then database_token_authorized?(token, required_scope)
      else env_secret_authorized?(token)
      end
    end

    def env_secret_authorized?(token)
      expected = WarpEngine.config.update_secret
      # With no secret configured the endpoint stays closed.
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
    end

    def database_token_authorized?(token, required_scope)
      if WarpEngine.config.application_token_owner_class.blank?
        Rails.logger.error("[#{self.class.name}] application_token_source=:database but application_token_owner_class is not set — rejecting every request")
        return false
      end

      record = WarpEngine::ApplicationToken.authenticate(token, required_scope: required_scope)
      return false if record.nil?

      record.touch_last_used!
      @current_application_token = record
      true
    end

    # Ownership enforcement applies only in :database mode (there is a token)
    # with enforce_software_ownership on. An ownerless software is up for grabs
    # until the backfill — backfill before enabling the enforcement.
    def software_ownership_authorized?(name)
      return true unless WarpEngine.config.enforce_software_ownership

      token = current_application_token
      return true if token.nil? || token.unrestricted?

      software = WarpEngine::Software.find_by(name: name)
      return true if software.nil? || software.owner_id.nil?

      software.owner_type == token.owner_type && software.owner_id == token.owner_id
    end

    # A first-published (or pre-backfill, ownerless) software gets the
    # submitting token's owner. Unrestricted (internal) tokens claim nothing.
    def claim_software_ownership(name)
      token = current_application_token
      return if token.nil? || token.unrestricted?

      software = WarpEngine::Software.find_by(name: name)
      return if software.nil? || software.owner_id.present?

      software.update_columns(owner_type: token.owner_type, owner_id: token.owner_id)
    end
  end
end
