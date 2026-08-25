require "warp_engine/access_denied"

module WarpEngine
  class ApiController < ActionController::API
    resource_description do
      api_version "1.0"
      formats [ "json" ]
    end

    before_action :set_version_header

    include WarpEngine::ApiErrorRendering
    include WarpEngine::SubjectAuthentication

    rescue_from WarpEngine::AccessDenied do
      render json: { error: "Forbidden" }, status: :forbidden
    end

    private

    def set_version_header
      response.headers["WarpEngine-Version"] = WarpEngine::VERSION
    end
  end
end
