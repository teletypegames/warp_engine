require "digest"

module WarpEngine
  module Build
    # Receives build artifacts from CI into the file container. Needs a credential
    # with the upload scope in <tt>X-Update-Secret</tt> (see
    # WarpEngine::UpdateAuthentication).
    class UploadsController < ApiController
      include UpdateAuthentication

      # The scopes that may upload: the CI's and another engine's.
      UPLOAD_SCOPES = [ WarpEngine::ApplicationToken::UPLOAD_SCOPE, WarpEngine::ApplicationToken::SYNC_SCOPE ].freeze

      resource_description do
        short "Build artifact upload"
      end

      api :POST, "/build/upload", "Upload a build artifact into the folder of its release"
      header "X-Update-Secret", "Shared secret or application token (upload or sync scope)", required: true
      param :name, String, required: true, desc: "Software name (filename must be prefixed with <name>-<version>)"
      param :version, String, required: true, desc: "Version string"
      param :file, File, required: true, desc: "Artifact file (multipart)"
      param :sha256, String, required: false, desc: "Expected SHA256 hex digest; on mismatch the upload is rejected"
      param :platform, String, required: false, desc: "The platform, for a sync peer's push: the inbound lists check it before the file lands"
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
      # [platform] optional platform, which a sync push sends so the inbound
      #            lists can refuse the file before it is stored
      #
      # Stores the file in the release's folder (WarpEngine::ReleaseLayout)
      # through WarpEngine::FileManagerService and renders
      # <tt>{ "file", "size", "sha256" }</tt>. A token with the +upload+ or the
      # +sync+ scope is accepted, the latter only as far as
      # WarpEngine::SyncInboundService takes it (403 otherwise). Responds 401 without a valid credential, 400
      # for invalid input (WarpEngine::UploadInputDto), 403 when the token does
      # not own the software, 413 above +max_upload_size+ and 422 on a digest
      # mismatch.
      def create
        unless update_authorized?(required_scope: UPLOAD_SCOPES)
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end

        input = WarpEngine::UploadInputDto.new(
          name:    params[:name].to_s,
          version: params[:version].to_s,
          file:    params[:file],
          sha256:  params[:sha256]
        )
        return render json: { error: input.error_message }, status: :bad_request unless input.valid?

        if sync_request? && (refusal = WarpEngine::SyncInboundService.new.refuse_upload(token: current_application_token,
                                                                                         name: input.name, version: input.version,
                                                                                         platform: params[:platform].to_s))
          return render json: { error: refusal.message }, status: refusal.status
        end

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

        stored = WarpEngine::FileManagerService.new.upload(WarpEngine::ReleaseLayout.directory(input.name, input.version), input.file, create: true)
        render json: { file: stored, size: input.file.size, sha256: digest }
      end
    end
  end
end
