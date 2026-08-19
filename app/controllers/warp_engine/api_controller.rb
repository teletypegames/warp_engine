module WarpEngine
  class ApiController < ActionController::API
    resource_description do
      api_version "1.0"
      formats [ "json" ]
    end

    # Every response the engine serves names the version that served it, so a client can
    # branch on the engine's age without a round trip to ask. Set *before* the action,
    # not after: an error handled by `rescue_from` never reaches an after_action, and a
    # client needs the version most when something came back wrong.
    before_action :set_version_header

    # Every read-only endpoint may be called with a bearer token; none of them requires
    # one. See WarpEngine::SubjectAuthentication.
    include WarpEngine::SubjectAuthentication

    rescue_from StandardError do |e|
      Rails.logger.error("[#{self.class.name}] #{e.class}: #{e.message}")
      render json: { error: "Internal server error" }, status: :internal_server_error
    end

    rescue_from ActiveRecord::RecordNotFound do |e|
      render json: { error: "Not found" }, status: :not_found
    end

    rescue_from Errno::ENOENT do |e|
      render json: { error: "Not found" }, status: :not_found
    end

    rescue_from ArgumentError do |e|
      render json: { error: e.message }, status: :bad_request
    end

    rescue_from WarpEngine::DownloadService::Denied do
      render json: { error: "Forbidden" }, status: :forbidden
    end

    private

    def set_version_header
      # The name is spelled out here rather than taken from WarpEngine::VERSION_HEADER on
      # purpose. A deployed process can end up with these controllers and an older
      # `lib/` — it happened on the first deploy of this feature — and a controller that
      # needs a constant from the newer half answers 500 to every request instead of
      # serving the catalog. A response header is not worth that fragility. The constant
      # is still the documented name, and a spec holds the two together.
      response.headers["WarpEngine-Version"] = WarpEngine::VERSION
    end

    def resolve_mime(path)
      ext = File.extname(path.to_s).delete_prefix(".")
      Mime::Type.lookup_by_extension(ext) || "application/octet-stream"
    end
  end
end
