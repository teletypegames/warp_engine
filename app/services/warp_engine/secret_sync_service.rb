module WarpEngine
  class SecretSyncService
    SECRET_NAME = "application_token".freeze

    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    def provision(plain_token, pipelines:)
      results = { synced: [], failed: [] }

      Array(pipelines).each do |pipeline|
        @ci.secret_set(pipeline.remote_repo_id, name: SECRET_NAME, value: plain_token)
        results[:synced] << pipeline
      rescue CI::Error => e
        Rails.logger.error("[SecretSyncService] failed for #{pipeline.full_name}: #{e.message}")
        results[:failed] << { pipeline: pipeline, error: e.message }
      end

      results
    end

    def remove(pipelines:)
      Array(pipelines).each do |pipeline|
        @ci.secret_delete(pipeline.remote_repo_id, SECRET_NAME)
      rescue CI::Error => e
        Rails.logger.warn("[SecretSyncService] delete failed for #{pipeline.full_name}: #{e.message}")
      end
    end

    def deprovision(application_token)
      remove(pipelines: pipelines_for_token(application_token))
    end

    def rotate(application_token)
      pipelines = pipelines_for_token(application_token)
      return { rotated: false, reason: "no pipelines" } if pipelines.empty?

      new_token = ApplicationToken.create!(
        name:         "#{application_token.name} (rotated #{Date.current})",
        owner_id:     application_token.owner_id,
        owner_type:   application_token.owner_type,
        scopes:       application_token.scopes,
        expires_at:   application_token.expires_at,
        unrestricted: application_token.unrestricted?
      )

      result = provision(new_token.plain_token, pipelines: pipelines)

      if result[:synced].any?
        application_token.revoke!
        { rotated: true, new_token: new_token, sync_result: result }
      else
        new_token.revoke!
        { rotated: false, reason: "all pipelines failed", sync_result: result }
      end
    end

    def pipelines_for_token(application_token)
      if application_token.unrestricted?
        Pipeline.active.to_a
      else
        software_ids = Software.where(
          owner_type: application_token.owner_type,
          owner_id:   application_token.owner_id
        ).pluck(:id)
        Pipeline.active.where(software_id: software_ids).to_a
      end
    end
  end
end
