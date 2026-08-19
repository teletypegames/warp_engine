module WarpEngine
  # The device authorization grant, client side (RFC 8628).
  #
  # Both actions are unauthenticated, and have to be: the whole point of the flow is
  # that the caller has no credential yet. What protects it is that a device code is
  # useless until a signed-in person approves it on the host's own page.
  class Api::Auth::DevicesController < ApiController
    before_action :ensure_identity_configured

    resource_description do
      short "Device sign-in"
    end

    api :POST, "/api/auth/device", "Start a device sign-in and get a code pair"
    param :client_name, String, required: false, desc: "What to call this device in the person's account"
    returns code: 200, desc: "The code pair and where to take it"
    error code: 404, desc: "This deployment has no client sign-in"
    def create
      grant = service.request(client_name: params[:client_name])

      render json: {
        deviceCode:      grant.device_code,
        userCode:        grant.formatted_user_code,
        verificationUrl: service.verification_url(base_url: request.base_url),
        interval:        WarpEngine.config.device_code_interval.to_i,
        expiresIn:       (grant.expires_at - Time.current).to_i
      }
    end

    api :POST, "/api/auth/device/token", "Poll a device sign-in for its token"
    param :device_code, String, required: true, desc: "The device code from POST /api/auth/device"
    returns code: 200, desc: "state is one of pending, approved, denied, expired"
    error code: 404, desc: "No such device code, or no client sign-in here"
    def token
      state, plain = service.poll(device_code: params[:device_code])

      # The token rides on the one poll that finds the grant newly approved; a client
      # that loses it starts the flow again. Keeping a plain token around to hand out
      # twice would mean storing it, which is the thing this design avoids.
      body = { state: state.to_s }
      body[:token] = plain if plain.present?
      render json: body
    rescue WarpEngine::DeviceGrantService::UnknownCode
      render json: { error: "Not found" }, status: :not_found
    end

    private

    def service
      @service ||= WarpEngine::DeviceGrantService.new
    end

    # A deployment with no configured subject class has no sign-in at all, and says so
    # the same way GET /api/service does — by not offering it.
    def ensure_identity_configured
      return if WarpEngine.identity_configured?

      render json: { error: "Not found" }, status: :not_found
    end
  end
end
