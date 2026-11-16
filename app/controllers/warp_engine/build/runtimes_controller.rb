module WarpEngine
  module Build
    # Receives a version of an uploaded runtime (one declared with
    # <tt>source :upload</tt>) from a build. Needs a credential with the upload
    # scope in <tt>X-Update-Secret</tt> (see WarpEngine::UpdateAuthentication);
    # a database token restricted to its owner's softwares may not send one.
    class RuntimesController < ApiController
      include UpdateAuthentication

      resource_description do
        short "Runtime upload"
      end

      api :POST, "/build/runtime", "Install a version of an uploaded runtime from a zip"
      header "X-Update-Secret", "Shared secret or application token (upload scope)", required: true
      param :name, String, required: true, desc: "Runtime name"
      param :version, String, required: true, desc: "Runtime version"
      param :file, File, required: true, desc: "Zip holding the runtime's files (multipart)"
      returns code: 200, desc: "The version was there with the same files"
      returns code: 201, desc: "The version was installed"
      error code: 401, desc: "Invalid secret"
      error code: 403, desc: "The token is restricted to its owner's softwares"
      error code: 400, desc: "Missing file"
      error code: 409, desc: "The version is installed with other files"
      error code: 413, desc: "File larger than max_upload_size"
      error code: 422, desc: "Unknown runtime, malformed version or incomplete zip"
      # <tt>POST /build/runtime</tt> (multipart: +name+, +version+, +file+).
      #
      # Installs the zip through WarpEngine::RuntimeUploadService and renders
      # <tt>{ "name", "version", "files" }</tt> with 201 (installed) or 200
      # (already there with the same files). Responds 401 without a valid
      # credential, 403 for a restricted token, 400 without a file, 413 above
      # +max_upload_size+, 409 when the version holds other files and 422 for
      # any other refusal.
      def create
        unless update_authorized?(required_scope: WarpEngine::ApplicationToken::UPLOAD_SCOPE)
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end
        return render json: { error: "Forbidden" }, status: :forbidden if restricted_token?

        file = params[:file]
        return render json: { error: "file is required" }, status: :bad_request unless file.respond_to?(:tempfile)

        max = WarpEngine.config.max_upload_size
        return render json: { error: "File too large" }, status: :payload_too_large if file.size > max

        result = WarpEngine::RuntimeUploadService.new.upload(name: params[:name].to_s, version: params[:version].to_s,
                                                             zip_path: file.tempfile.path)
        version = result.runtime_version
        render json: { name: version.name, version: version.version, files: version.file_digests },
               status: result.created ? :created : :ok
      rescue WarpEngine::RuntimeUploadService::Conflict => e
        render json: { error: e.message }, status: :conflict
      rescue WarpEngine::RuntimeUploadService::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def restricted_token?
        WarpEngine.config.enforce_software_ownership && current_application_token&.unrestricted? == false
      end
    end
  end
end
