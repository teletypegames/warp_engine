module WarpEngine
  class ApiController < ActionController::API
    resource_description do
      api_version "1.0"
      formats [ "json" ]
    end

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

    def resolve_mime(path)
      ext = File.extname(path.to_s).delete_prefix(".")
      Mime::Type.lookup_by_extension(ext) || "application/octet-stream"
    end
  end
end
