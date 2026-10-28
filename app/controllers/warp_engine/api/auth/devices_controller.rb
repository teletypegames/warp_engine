module WarpEngine
  module Api
    module Auth
      # Starts the device authorization grant a client without a browser of its
      # own uses to sign in.
      class DevicesController < BaseController
        resource_description do
          short "Device sign-in"
        end

        api :POST, "/api/auth/device", "Start a device sign-in and get a code pair"
        param :client_name, String, required: false, desc: "What to call this device in the person's account"
        returns code: 200, desc: "The code pair and where to take it"
        error code: 404, desc: "This deployment has no client sign-in"
        # <tt>POST /api/auth/device</tt>.
        #
        # [client_name] optional name of the device, shown in the person's account
        #
        # Creates a WarpEngine::DeviceGrant and renders it through
        # WarpEngine::DeviceGrantSerializer: the device and user codes, the
        # verification URL to open, the polling interval and the seconds until expiry.
        def create
          grant = service.request(client_name: params[:client_name])

          render json: WarpEngine::DeviceGrantSerializer.render_as_hash(
            grant, verification_url: service.verification_url(base_url: request.base_url)
          )
        end
      end
    end
  end
end
