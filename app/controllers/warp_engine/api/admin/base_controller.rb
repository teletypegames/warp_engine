module WarpEngine
  # Namespace of the controllers under <tt>/api</tt>: the public catalog API,
  # client sign-in, CI pipelines and the Admin API.
  module Api
    # Namespace of the Admin API controllers, mounted under
    # WarpEngine::AdminApi.url_path.
    module Admin
      # Base controller of the Admin API.
      #
      # Every response carries the Admin API version header
      # (WarpEngine::AdminApi::HEADER). Responds 404 for everything while the Admin
      # API is disabled. A raised WarpEngine::AdminApi::Error is rendered as its
      # JSON body with its status and headers. Subclasses call the private
      # +authenticate!+, which requires an admin bearer token
      # (WarpEngine::AdminApi::Authenticator, 401 without one) and applies the
      # rate limit (429 with <tt>Retry-After</tt>).
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
