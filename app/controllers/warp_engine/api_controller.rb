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

    private

    def set_version_header
      response.headers[WarpEngine::VERSION_HEADER] = WarpEngine::VERSION
    end

    def resolve_mime(path)
      ext = File.extname(path.to_s).delete_prefix(".")
      Mime::Type.lookup_by_extension(ext) || "application/octet-stream"
    end
  end
end
