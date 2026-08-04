module WarpEngine
  class DownloadService
    def self.container_base
      WarpEngine.config.file_container_path
    end

    # Lazy: a container path csak az első használatkor kötelező, boot/teszt közben nem.
    def self.base_path
      Pathname.new(container_base).realpath
    end

    def create(path:, ip:, user_agent:, referer:)
      sanitized = path.to_s
      base_path = self.class.base_path
      full_path = base_path.join(sanitized).realpath
      return nil unless full_path.to_s.start_with?(base_path.to_s)
      return nil unless File.file?(full_path)

      escaped = sanitized.gsub("%", "\\%").gsub("_", "\\_")
      asset = WarpEngine::ReleaseAsset.find_by(path: File.join(self.class.container_base, sanitized)) ||
              WarpEngine::ReleaseAsset.where("path LIKE ?", "%#{escaped}%").first

      WarpEngine::Download.create!(
        file_path: sanitized,
        release: asset&.release,
        ip_address: ip,
        user_agent: user_agent&.truncate(500),
        referer: referer&.truncate(500)
      )

      full_path
    end
  end
end
