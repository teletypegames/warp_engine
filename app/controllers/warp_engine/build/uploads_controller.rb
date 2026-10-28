require "digest"

module WarpEngine
  module Build
    # Receives build artifacts from CI into the file container. Needs a credential
    # with the upload scope in <tt>X-Update-Secret</tt> (see
    # WarpEngine::UpdateAuthentication).
    class UploadsController < ApiController
      include UpdateAuthentication

      resource_description do
        short "Build artifact upload"
      end

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
      # <tt>POST /build/upload</tt> (multipart).
      #
      # [name]    the software name
      # [version] the version string
      # [file]    the artifact, its file name prefixed with <tt><name>-<version></tt>
      # [sha256]  optional expected SHA-256 hex digest
      #
      # Stores the file through WarpEngine::FileManagerService and renders
      # <tt>{ "file", "size", "sha256" }</tt>. Responds 401 without a valid
      # credential, 400 for invalid input (WarpEngine::UploadInputDto), 403 when
      # the token does not own the software, 413 above +max_upload_size+ and 422
      # on a digest mismatch.
      def create
        unless update_authorized?(required_scope: WarpEngine::ApplicationToken::UPLOAD_SCOPE)
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end

        input = WarpEngine::UploadInputDto.new(
          name:    params[:name].to_s,
          version: params[:version].to_s,
          file:    params[:file],
          sha256:  params[:sha256]
        )
        return render json: { error: input.error_message }, status: :bad_request unless input.valid?

        unless software_ownership_authorized?(input.name)
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        max = WarpEngine.config.max_upload_size
        if input.file.size > max
          return render json: { error: "File too large (max #{max / (1024 * 1024)}MB)" }, status: :payload_too_large
        end

        digest = Digest::SHA256.file(input.file.tempfile.path).hexdigest
        if input.sha256.present? && !ActiveSupport::SecurityUtils.secure_compare(input.sha256.downcase, digest)
          return render json: { error: "SHA256 mismatch" }, status: :unprocessable_entity
        end

        stored = WarpEngine::FileManagerService.new.upload("", input.file)
        render json: { file: stored, size: input.file.size, sha256: digest }
      end
    end
  end
end
