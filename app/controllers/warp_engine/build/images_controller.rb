module WarpEngine
  module Build
    # Sets a software's gallery from another engine (a sync push) or the CI:
    # a manifest of images by SHA-256, and the files the gallery lacks. Needs
    # the update credential, or a token with the +update+ or +sync+ scope, in
    # <tt>X-Update-Secret</tt> (see WarpEngine::UpdateAuthentication).
    class ImagesController < ApiController
      include UpdateAuthentication

      # The scopes that may set a gallery: the CI's and another engine's.
      IMAGE_SCOPES = [ WarpEngine::ApplicationToken::UPDATE_SCOPE, WarpEngine::ApplicationToken::SYNC_SCOPE ].freeze

      resource_description do
        short "Software images from sync"
      end

      api :POST, "/build/images", "Make a software's gallery follow a manifest of images by SHA-256"
      header "X-Update-Secret", "Shared secret or application token (update or sync scope)", required: true
      param :name, String, required: true, desc: "Software name"
      param :images, Array, required: true, desc: "In order: { sha256, filename, contentType, default }"
      returns code: 200, desc: %(JSON {"applied": true|false, "missing": [sha256, ...]})
      error code: 401, desc: "Invalid secret"
      error code: 403, desc: "Token does not own this software, or the inbound lists refuse it"
      error code: 409, desc: "No such software here, or its images were set here (protect_local)"
      error code: 400, desc: "Invalid manifest"
      # <tt>POST /build/images</tt> (JSON).
      #
      # [name]   the software name
      # [images] the gallery in order, each <tt>{ sha256, filename, contentType, default }</tt>
      #
      # Through WarpEngine::SyncImagesService#apply: when every image is here
      # by digest, orders them and unlinks the rest, and renders
      # <tt>{ "applied": true, "missing": [] }</tt>; otherwise renders
      # <tt>{ "applied": false, "missing": [...] }</tt> with the digests to
      # upload first. A sync token's push is checked by
      # WarpEngine::SyncInboundService#refuse_images and marks the images
      # +sync+. Responds 401, 400, 403 and 409 as listed.
      def create
        software = authorized_software
        return if performed?

        entries = WarpEngine::SyncImagesService.entries(params.to_unsafe_h["images"])
        outcome = WarpEngine::SyncImagesService.new.apply(software, entries, origin: origin)
        render json: { applied: outcome.applied, missing: outcome.missing }
      rescue WarpEngine::SyncImagesService::InvalidManifest => e
        render json: { error: e.message }, status: :bad_request
      end

      api :POST, "/build/images/upload", "Add one image a manifest named as missing"
      header "X-Update-Secret", "Shared secret or application token (update or sync scope)", required: true
      param :name, String, required: true, desc: "Software name"
      param :sha256, String, required: true, desc: "The image's SHA256 hex digest"
      param :file, File, required: true, desc: "The image (multipart)"
      returns code: 200, desc: %(JSON {"id": ..., "sha256": ...})
      error code: 422, desc: "SHA256 mismatch, or not an image the library takes"
      # <tt>POST /build/images/upload</tt> (multipart).
      #
      # [name]   the software name
      # [sha256] the image's SHA-256 hex digest
      # [file]   the image
      #
      # Adds the image to the library and the end of the gallery through
      # WarpEngine::SyncImagesService#add (nothing when it is there by digest)
      # and renders <tt>{ "id", "sha256" }</tt>. Responds 400 without a file or
      # with a bad digest, 422 on a mismatch or an invalid image, and 401, 403
      # and 409 like #create.
      def upload
        software = authorized_software
        return if performed?

        file = params[:file]
        sha = params[:sha256].to_s.downcase
        unless file.respond_to?(:tempfile) && sha.match?(WarpEngine::SyncImagesService::SHA256)
          return render json: { error: "file and sha256 are required" }, status: :bad_request
        end
        if file.size > WarpEngine.config.max_upload_size
          return render json: { error: "File too large" }, status: :payload_too_large
        end

        link = WarpEngine::SyncImagesService.new.add(software, file, sha256: sha, origin: origin)
        render json: { id: link.id, sha256: sha }
      rescue WarpEngine::SyncImagesService::DigestMismatch => e
        render json: { error: e.message }, status: :unprocessable_content
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_content
      end

      private

      def origin = sync_request? ? "sync" : "local"

      def authorized_software
        return render(json: { error: "Unauthorized" }, status: :unauthorized) unless update_authorized?(required_scope: IMAGE_SCOPES)

        name = params[:name].to_s
        return render(json: { error: "name is required" }, status: :bad_request) if name.blank?
        return render(json: { error: "Forbidden" }, status: :forbidden) unless software_ownership_authorized?(name)

        software = WarpEngine::Software.kept.find_by(name: name)
        if sync_request? && (refusal = WarpEngine::SyncInboundService.new.refuse_images(token: current_application_token, software: software))
          return render(json: { error: refusal.message }, status: refusal.status)
        end
        return render(json: { error: "no such software here" }, status: :conflict) if software.nil?

        software
      end
    end
  end
end
