module WarpEngine
  # Base controller of every WarpEngine JSON endpoint.
  #
  # Adds the <tt>WarpEngine-Version</tt> response header to every response
  # (WarpEngine::VersionHeader),
  # renders errors through WarpEngine::ApiErrorRendering, resolves the caller
  # through WarpEngine::SubjectAuthentication, and answers 403
  # <tt>{ "error": "Forbidden" }</tt> when an access policy raises
  # WarpEngine::AccessDenied.
  class ApiController < ActionController::API
    resource_description do
      api_version "1.0"
      formats [ "json" ]
    end

    include WarpEngine::VersionHeader
    include WarpEngine::ApiErrorRendering
    include WarpEngine::SubjectAuthentication

    rescue_from WarpEngine::AccessDenied do
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end
end
