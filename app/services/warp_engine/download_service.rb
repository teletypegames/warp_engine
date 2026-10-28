require "warp_engine/access_denied"

module WarpEngine
  # Serves a download from the file container: checks the access policy, logs a
  # WarpEngine::Download and locates the file in the storage adapter.
  class DownloadService
    # Alias of WarpEngine::AccessDenied, the error a refused download raises.
    Denied = WarpEngine::AccessDenied

    include AccessPolicyGuard

    # Locates the file at +path+ (relative to the storage) for download.
    #
    # [path]       the file path, relative to the storage root
    # [ip]         the client IP, logged
    # [user_agent] the client user agent, logged (truncated to 500 characters)
    # [referer]    the referer, logged (truncated to 500 characters)
    # [subject]    the caller, or +nil+ when anonymous
    # [request]    the Rack request, passed to the access policy
    #
    # Returns the WarpEngine::Storage::Location of the file (a local path or a
    # redirect URL, named and expiring as the policy's grant says), or +nil+ when
    # there is no such file. Writes a WarpEngine::Download and instruments
    # <tt>warp_engine.download</tt> unless the user agent is ignored
    # (<tt>WarpEngine.config.ignored_user_agent?</tt>). Raises Denied when the
    # access policy refuses.
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

    # Like #locate, but returns the local file path, or +nil+ when there is no
    # such file or the storage answers with a redirect.
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
