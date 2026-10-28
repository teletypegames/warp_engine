module WarpEngine
  module Api
    module Auth
      # The polling half of the device authorization grant: a client trades its
      # device code for a token once the person has approved the sign-in.
      class DeviceTokensController < BaseController
        resource_description do
          short "Device sign-in polling"
        end

        api :POST, "/api/auth/device/token", "Poll a device sign-in for its token"
        param :device_code, String, required: true, desc: "The device code from POST /api/auth/device"
        returns code: 200, desc: "state is one of pending, approved, denied, expired"
        error code: 404, desc: "No such device code, or no client sign-in here"
        # <tt>POST /api/auth/device/token</tt>.
        #
        # [device_code] the device code from <tt>POST /api/auth/device</tt>
        #
        # Renders <tt>{ "state": ... }</tt>, the grant's state (+pending+,
        # +approved+, +denied+ or +expired+), plus +token+, the plain bearer token,
        # in the one response that hands it over. Responds 404 for an unknown device
        # code.
        def create
          state, plain = service.poll(device_code: params[:device_code])

          body = { state: state.to_s }
          body[:token] = plain if plain.present?

          render json: body
        rescue WarpEngine::DeviceGrantService::UnknownCode
          render json: { error: "Not found" }, status: :not_found
        end
      end
    end
  end
end
