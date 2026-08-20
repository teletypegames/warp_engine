module WarpEngine
  class DownloadService

    class Denied < StandardError; end

    def self.container_base
      WarpEngine.config.file_container_path
    end

    def self.base_path
      Pathname.new(container_base).realpath
    end

    def locate(path:, ip:, user_agent:, referer:, subject: nil, request: nil)
      relative = path.to_s
      return nil unless storage.file?(relative)

      asset = find_asset(relative)
      grant = authorize!(asset, subject, request)

      log_download(relative, asset: asset, ip: ip, user_agent: user_agent, referer: referer, subject: subject)

      storage.locate(relative,
                     filename: grant.filename.presence || File.basename(relative),
                     expires_in: grant.expires_in)
    end

    def create(path:, ip:, user_agent:, referer:, subject: nil, request: nil)
      location = locate(path: path, ip: ip, user_agent: user_agent, referer: referer,
                        subject: subject, request: request)
      return nil if location.nil?

      location.file? ? location.path : nil
    end

    private

    def storage
      WarpEngine.storage
    end

    def authorize!(asset, subject, request)
      grant = WarpEngine.access_policy.authorize_download(asset: asset, subject: subject, request: request)
      raise Denied if grant.nil?

      grant
    rescue Denied
      raise
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::AccessPolicy] #{e.class}: #{e.message}")
      raise Denied
    end

    def find_asset(relative)
      escaped = relative.gsub("%", "\\%").gsub("_", "\\_")
      WarpEngine::ReleaseAsset.find_by(path: File.join(self.class.container_base, relative)) ||
        WarpEngine::ReleaseAsset.where("path LIKE ?", "%#{escaped}%").first
    end

    def log_download(relative, asset:, ip:, user_agent:, referer:, subject:)
      download = WarpEngine::Download.create!(
        file_path: relative,
        release: asset&.release,
        ip_address: ip,
        user_agent: user_agent&.truncate(500),
        referer: referer&.truncate(500)
      )

      ActiveSupport::Notifications.instrument("warp_engine.download",
        path: relative, asset: asset, release: asset&.release,
        software: asset&.release&.software, subject: subject, download: download, ip: ip)
    end
  end
end
