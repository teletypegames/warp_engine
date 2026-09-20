module WarpEngine
  class Api::Auth::DeviceTokensController < Api::Auth::BaseController
    resource_description do
      short "Device sign-in polling"
    end

    api :POST, "/api/auth/device/token", "Poll a device sign-in for its token"
    param :device_code, String, required: true, desc: "The device code from POST /api/auth/device"
    returns code: 200, desc: "state is one of pending, approved, denied, expired"
    error code: 404, desc: "No such device code, or no client sign-in here"
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
