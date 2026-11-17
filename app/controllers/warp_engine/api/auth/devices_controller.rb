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
        param :scopes, Array, required: false, desc: "Admin API scopes a tool asks for (admin:read, admin:write, admin:tokens); an administrator approves them"
        returns code: 200, desc: "The code pair and where to take it"
        error code: 404, desc: "This deployment has no client sign-in (or, for a tool, no Admin API)"
        error code: 422, desc: "A scope that is no Admin API scope"
        # <tt>POST /api/auth/device</tt>.
        #
        # [client_name] optional name of the device, shown in the person's account
        # [scopes]      Admin API scopes a tool asks for; the grant is then
        #               approved by an administrator on the tool verification page
        #
        # Creates a WarpEngine::DeviceGrant and renders it through
        # WarpEngine::DeviceGrantSerializer: the device and user codes, the
        # verification URL to open, the polling interval and the seconds until expiry.
        def create
          grant = service.request(client_name: params[:client_name], scopes: params[:scopes])
          url = if grant.tool?
            service.tool_verification_url(base_url: request.base_url)
          else
            service.verification_url(base_url: request.base_url)
          end

          render json: WarpEngine::DeviceGrantSerializer.render_as_hash(grant, verification_url: url)
        rescue WarpEngine::DeviceGrantService::InvalidScopes => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
