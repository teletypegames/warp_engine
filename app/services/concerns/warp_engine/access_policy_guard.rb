module WarpEngine
  module AccessPolicyGuard
    private

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
