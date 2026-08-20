module WarpEngine

  module SubjectAuthentication
    extend ActiveSupport::Concern

    private

    def current_access_token
      return @current_access_token if defined?(@current_access_token)

      @current_access_token = resolve_access_token
    end

    def current_subject
      return @current_subject if defined?(@current_subject)

      @current_subject = current_access_token&.owner || resolve_host_subject
    end

    def resolve_access_token
      return nil unless WarpEngine.identity_configured?

      token = bearer_token
      return nil if token.blank?

      record = WarpEngine::ApplicationToken.authenticate(
        token, required_scope: WarpEngine::ApplicationToken::CATALOG_SCOPE
      )
      return nil if record.nil?

      record.touch_last_used!
      record
    end

    def resolve_host_subject
      resolver = WarpEngine.config.subject_resolver
      return nil if resolver.nil?

      resolver.call(request)
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::SubjectAuthentication] subject_resolver #{e.class}: #{e.message}")
      nil
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      return nil unless header.start_with?("Bearer ")

      header.delete_prefix("Bearer ").strip.presence
    end
  end
end
