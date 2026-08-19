module WarpEngine
  class FileService
    # Lazy: a container path csak az első használatkor kötelező, boot/teszt közben nem.
    def self.base_path
      Pathname.new(WarpEngine.config.file_container_path).realpath
    end

    # A fájlok helyét a storage adapter adja (alapból :local, azaz a lemez) —
    # így a host az objektumtárból is kiszolgálhat anélkül, hogy az engine-t
    # patchelné. Lásd WarpEngine::Storage.
    # `subject` is whoever the request authenticated as, or nil. Under the open policy
    # it is ignored and every file is served, exactly as before.
    #
    # A hosted (browser) build reaches this path as hundreds of relative requests for
    # js, wasm and images, which is why the gate here is the policy's plain yes/no
    # rather than anything signed: there is nothing to sign per file. A host serving
    # gated web builds to browsers will usually want its own session-based route in
    # front of this one — a browser has a session, and a redirect to a login page is a
    # better answer there than a bare 403.
    def show(input, subject: nil)
      relative = input.path.to_s

      if storage.directory?(relative)
        index = File.join(relative.chomp("/"), "index.html")
        return FileResultDto.not_found unless storage.file?(index)

        return FileResultDto.redirect("/file/#{index}")
      end

      return FileResultDto.not_found unless storage.file?(relative)

      authorize!(relative, subject)

      to_result(storage.locate(relative, filename: File.basename(relative)))
    end

    private

    # Same rule and same failure mode as DownloadService: a policy that refuses or
    # raises means no file. An artifact served because the gatekeeper crashed is the
    # one failure mode this engine must not have.
    def authorize!(relative, subject)
      # The open policy authorises everything, and this path serves a browser build as
      # hundreds of requests for js, wasm and images. Asking it per file would mean a
      # LIKE query per asset for an answer that is always yes.
      return WarpEngine::Access::Grant::OPEN if WarpEngine::AccessPolicy.open?

      asset = WarpEngine::ReleaseAsset.where("path LIKE ?", "%#{relative.gsub('%', '\\%').gsub('_', '\\_')}%").first
      grant = WarpEngine.access_policy.authorize_download(asset: asset, subject: subject, request: nil)
      raise WarpEngine::DownloadService::Denied if grant.nil?

      grant
    rescue WarpEngine::DownloadService::Denied
      raise
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::AccessPolicy] #{e.class}: #{e.message}")
      raise WarpEngine::DownloadService::Denied
    end

    def storage
      WarpEngine.storage
    end

    def to_result(location)
      location.redirect? ? FileResultDto.redirect(location.url) : FileResultDto.file(location.path)
    end
  end
end
