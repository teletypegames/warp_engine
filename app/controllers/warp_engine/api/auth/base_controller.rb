module WarpEngine
  module Api
    # Namespace of the client sign-in endpoints under <tt>/api/auth</tt>.
    module Auth
      # Base controller of the device sign-in endpoints under <tt>/api/auth/device</tt>.
      #
      # Responds 404 <tt>{ "error": "Not found" }</tt> when the sign-in asked for
      # is not configured (no client identity for a catalog client, no Admin API
      # for a tool), and gives subclasses a WarpEngine::DeviceGrantService
      # through the private +service+ helper.
      class BaseController < WarpEngine::ApiController
        rescue_from WarpEngine::DeviceGrantService::NotConfigured do
          render json: { error: "Not found" }, status: :not_found
        end

        private

        def service
          @service ||= WarpEngine::DeviceGrantService.new
        end
      end
    end
  end
end
