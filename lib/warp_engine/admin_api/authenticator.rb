module WarpEngine
  module AdminApi
    # Finds the Principal of an Admin API request.
    module Authenticator
      module_function

      # Authenticates +request+ with the configured Configuration#authenticator:
      # the default <tt>:application_token</tt> uses #from_application_token, anything
      # else is called with the request. Returns the Principal, or +nil+ when the
      # request is not authenticated or the authenticator raises (the error is logged).
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

      # Authenticates the bearer token of +request+ as an admin
      # WarpEngine::ApplicationToken owned by the configured owner class. Updates the
      # token's last used time and returns its Principal, or +nil+.
      def from_application_token(request)
        token = bearer_token(request)
        return nil if token.blank?

        record = ApplicationToken.authenticate(token)
        return nil if record.nil? || !record.admin?
        return nil unless record.owner_type == AdminApi.config.owner_class_name

        record.touch_last_used!
        Principal.from_token(record)
      end

      # The token from the <tt>Authorization: Bearer</tt> header of +request+, or +nil+.
      def bearer_token(request)
        header = request.headers["Authorization"].to_s
        return nil unless header.start_with?("Bearer ")

        header.delete_prefix("Bearer ").strip.presence
      end
    end
  end
end
