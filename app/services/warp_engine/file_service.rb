module WarpEngine
  class FileService

    def self.base_path
      Pathname.new(WarpEngine.config.file_container_path).realpath
    end

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

    def authorize!(relative, subject)

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
