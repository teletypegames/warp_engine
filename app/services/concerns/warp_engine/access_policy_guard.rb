module WarpEngine
  # Mixin for services that hand out files: asks the configured access policy
  # (WarpEngine.access_policy) whether a download may go ahead.
  module AccessPolicyGuard
    private

    # Asks the access policy to authorize the download of +asset+.
    #
    # [asset]   the WarpEngine::ReleaseAsset being downloaded, or +nil+ for a file no asset owns
    # [subject] the caller (the host's owner record), or +nil+ when anonymous
    # [request] the Rack request, passed on to the policy
    #
    # Returns the grant the policy answered with (filename, expiry). Raises
    # WarpEngine::AccessDenied when the policy answers +nil+ or raises; any other
    # error of the policy is logged first.
    def authorize_download!(asset:, subject:, request: nil)
      grant = WarpEngine.access_policy.authorize_download(asset: asset, subject: subject, request: request)
      raise WarpEngine::AccessDenied if grant.nil?
      grant
    rescue WarpEngine::AccessDenied
      raise
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::AccessPolicy] #{e.class}: #{e.message}")
      raise WarpEngine::AccessDenied
    end
  end
end
