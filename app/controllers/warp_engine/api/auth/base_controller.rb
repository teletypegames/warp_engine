module WarpEngine
  module Api
    # Namespace of the client sign-in endpoints under <tt>/api/auth</tt>.
    module Auth
      # Base controller of the device sign-in endpoints under <tt>/api/auth/device</tt>.
      #
      # Responds 404 <tt>{ "error": "Not found" }</tt> when the host has configured
      # no client identity, and gives subclasses a WarpEngine::DeviceGrantService
      # through the private +service+ helper.
      class BaseController < WarpEngine::ApiController
        before_action :ensure_identity_configured

        private

        def service
          @service ||= WarpEngine::DeviceGrantService.new
        end

        def ensure_identity_configured
          return if WarpEngine.identity_configured?

          render json: { error: "Not found" }, status: :not_found
        end
      end
    end
  end
end
