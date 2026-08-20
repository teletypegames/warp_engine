require "digest"

module WarpEngine
  module Build
    class UploadsController < ApiController
      include UpdateAuthentication

      resource_description do
        short "Build artifact upload"
      end

      NAME_FORMAT = /\A[A-Za-z0-9._-]+\z/

      api :POST, "/build/upload", "Upload a build artifact into the artifact directory"
      header "X-Update-Secret", "Shared secret or application token (upload scope)", required: true
      param :name, String, required: true, desc: "Software name (filename must be prefixed with <name>-<version>)"
      param :version, String, required: true, desc: "Version string"
      param :file, File, required: true, desc: "Artifact file (multipart)"
      param :sha256, String, required: false, desc: "Expected SHA256 hex digest; on mismatch the upload is rejected"
      returns code: 200, desc: "JSON with stored file name, size and sha256"
      error code: 401, desc: "Invalid secret"
      error code: 403, desc: "Token does not own this software"
      error code: 400, desc: "Missing or invalid arguments"
      error code: 413, desc: "File larger than max_upload_size"
      error code: 422, desc: "SHA256 mismatch"
      def create
        unless update_authorized?(required_scope: WarpEngine::ApplicationToken::UPLOAD_SCOPE)
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end

        name    = params[:name].to_s
        version = params[:version].to_s
        file    = params[:file]

        return render json: { error: "Invalid name" },       status: :bad_request unless name.match?(NAME_FORMAT)
        return render json: { error: "Invalid version" },    status: :bad_request unless version.match?(NAME_FORMAT)
        return render json: { error: "File not provided" },  status: :bad_request unless file.respond_to?(:original_filename)

        unless software_ownership_authorized?(name)
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        filename = File.basename(file.original_filename.to_s)
        unless filename.start_with?("#{name}-#{version}.", "#{name}-#{version}-")
          return render json: { error: "Filename must be prefixed with #{name}-#{version}" }, status: :bad_request
        end

        max = WarpEngine.config.max_upload_size
        if file.size > max
          return render json: { error: "File too large (max #{max / (1024 * 1024)}MB)" }, status: :payload_too_large
        end

        digest = Digest::SHA256.file(file.tempfile.path).hexdigest
        if params[:sha256].present? && !ActiveSupport::SecurityUtils.secure_compare(params[:sha256].downcase, digest)
          return render json: { error: "SHA256 mismatch" }, status: :unprocessable_entity
        end

        stored = WarpEngine::FileManagerService.new.upload("", file)
        render json: { file: stored, size: file.size, sha256: digest }
      end
    end
  end
end
