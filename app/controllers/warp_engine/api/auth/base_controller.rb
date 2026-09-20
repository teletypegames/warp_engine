module WarpEngine
  class Api::Auth::BaseController < ApiController
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
