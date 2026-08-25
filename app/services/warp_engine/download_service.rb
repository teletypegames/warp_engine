require "warp_engine/access_denied"

module WarpEngine
  class DownloadService

    Denied = WarpEngine::AccessDenied

    include AccessPolicyGuard

    def locate(path:, ip:, user_agent:, referer:, subject: nil, request: nil)
      relative = path.to_s
      return nil unless storage.file?(relative)

      asset = find_asset(relative)
      grant = authorize_download!(asset: asset, subject: subject, request: request)

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

    def find_asset(relative)
      WarpEngine::ReleaseAsset.for_relative_path(relative)
    end

    def log_download(relative, asset:, ip:, user_agent:, referer:, subject:)
      return if WarpEngine.config.ignored_user_agent?(user_agent)

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
