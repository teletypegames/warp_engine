module WarpEngine

  module UpdateAuthentication
    extend ActiveSupport::Concern

    private

    attr_reader :current_application_token

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

    def software_ownership_authorized?(name)
      return true unless WarpEngine.config.enforce_software_ownership

      token = current_application_token
      return true if token.nil? || token.unrestricted?

      software = WarpEngine::Software.kept.find_by(name: name)
      return true if software.nil? || software.owner_id.nil?

      software.owner_type == token.owner_type && software.owner_id == token.owner_id
    end

    def claim_software_ownership(name)
      token = current_application_token
      return if token.nil? || token.unrestricted?

      software = WarpEngine::Software.kept.find_by(name: name)
      return if software.nil? || software.owner_id.present?

      software.update_columns(owner_type: token.owner_type, owner_id: token.owner_id)
    end
  end
end
