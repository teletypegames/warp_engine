require "warp_engine/access_denied"

module WarpEngine
  # Base controller of every WarpEngine JSON endpoint.
  #
  # Adds the <tt>WarpEngine-Version</tt> response header to every response,
  # renders errors through WarpEngine::ApiErrorRendering, resolves the caller
  # through WarpEngine::SubjectAuthentication, and answers 403
  # <tt>{ "error": "Forbidden" }</tt> when an access policy raises
  # WarpEngine::AccessDenied.
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
