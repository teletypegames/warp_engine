module WarpEngine
  module Api
    module Admin
      class BaseController < WarpEngine::ApiController
        wrap_parameters false

        before_action :set_admin_api_header
        before_action :require_enabled!

        rescue_from WarpEngine::AdminApi::Error, with: :render_admin_error

        private

        def admin_config = WarpEngine::AdminApi.config

        def set_admin_api_header
          response.headers[WarpEngine::AdminApi::HEADER] = WarpEngine::AdminApi::VERSION.to_s
        end

        def require_enabled!
          raise WarpEngine::AdminApi::Error.not_found unless admin_config.enabled?
        end

        def current_principal
          return @current_principal if defined?(@current_principal)

          @current_principal = WarpEngine::AdminApi::Authenticator.call(request)
        end

        def authenticate!
          raise WarpEngine::AdminApi::Error.unauthorized if current_principal.nil?

          throttle!
        end

        def throttle!
          return unless WarpEngine::AdminApi::RateLimiter.exceeded?(current_principal)

          raise WarpEngine::AdminApi::Error.new(
            429, "Too many requests",
            headers: { "Retry-After" => WarpEngine::AdminApi::RateLimiter.retry_after.to_s }
          )
        end

        def render_admin_error(error)
          error.headers.each { |name, value| response.headers[name] = value }
          render json: error.body, status: error.status
        end

        def engine_base_url = "#{request.base_url}#{request.script_name}"
        def server_url = "#{engine_base_url}#{WarpEngine::AdminApi.url_path}"
      end
    end
  end
end
