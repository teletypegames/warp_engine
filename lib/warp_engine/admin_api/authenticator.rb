module WarpEngine
  module AdminApi
    module Authenticator
      module_function

      def call(request)
        configured = AdminApi.config.authenticator
        principal = case configured
        when nil, :application_token, "application_token" then from_application_token(request)
        else configured.call(request)
        end
        principal.is_a?(Principal) ? principal : nil
      rescue StandardError => e
        Rails.logger.error("[WarpEngine::AdminApi] authenticator #{e.class}: #{e.message}")
        nil
      end

      def from_application_token(request)
        token = bearer_token(request)
        return nil if token.blank?

        record = ApplicationToken.authenticate(token)
        return nil if record.nil? || !record.admin?
        return nil unless record.owner_type == AdminApi.config.owner_class_name

        record.touch_last_used!
        Principal.from_token(record)
      end

      def bearer_token(request)
        header = request.headers["Authorization"].to_s
        return nil unless header.start_with?("Bearer ")

        header.delete_prefix("Bearer ").strip.presence
      end
    end
  end
end
