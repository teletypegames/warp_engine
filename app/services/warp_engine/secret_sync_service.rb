module WarpEngine
  # Writes application tokens into the secrets of CI pipelines, so a pipeline
  # can publish with them.
  class SecretSyncService
    # The name of the pipeline secret that holds the token.
    SECRET_NAME = "application_token".freeze

    # [ci] the CI adapter, by default WarpEngine.ci
    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    # Sets SECRET_NAME to +plain_token+ on every pipeline of +pipelines+. A
    # failing pipeline is logged and skipped. Returns a Hash with the +synced+
    # pipelines and the +failed+ ones (Hashes with +pipeline+ and +error+).
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

    # Deletes SECRET_NAME from every pipeline of +pipelines+; failures are logged.
    def remove(pipelines:)
      Array(pipelines).each do |pipeline|
        @ci.secret_delete(pipeline.remote_repo_id, SECRET_NAME)
      rescue CI::Error => e
        Rails.logger.warn("[SecretSyncService] delete failed for #{pipeline.full_name}: #{e.message}")
      end
    end

    # Deletes the secret from the pipelines of +application_token+ (#pipelines_for_token).
    def deprovision(application_token)
      remove(pipelines: pipelines_for_token(application_token))
    end

    # Replaces +application_token+: creates a copy (same owner, scopes, expiry
    # and restriction, named "... (rotated <date>)"), soft-deletes the old one and
    # provisions the new value to its pipelines. When no pipeline takes it, the
    # old token is restored and the new one soft-deleted.
    #
    # Returns a Hash: <tt>{ rotated: true, new_token:, sync_result: }</tt>, or
    # <tt>{ rotated: false, reason:, sync_result: }</tt> (no +sync_result+ when
    # there are no pipelines).
    def rotate(application_token)
      pipelines = pipelines_for_token(application_token)
      return { rotated: false, reason: "no pipelines" } if pipelines.empty?

      new_token = nil
      ActiveRecord::Base.transaction do
        new_token = ApplicationToken.create!(
          name:         "#{application_token.name} (rotated #{Date.current})",
          owner_id:     application_token.owner_id,
          owner_type:   application_token.owner_type,
          scopes:       application_token.scopes,
          expires_at:   application_token.expires_at,
          unrestricted: application_token.unrestricted?
        )
        application_token.soft_delete!
      end

      result = provision(new_token.plain_token, pipelines: pipelines)

      if result[:synced].any?
        { rotated: true, new_token: new_token, sync_result: result }
      else
        ActiveRecord::Base.transaction do
          application_token.restore!
          new_token.soft_delete!
        end
        { rotated: false, reason: "all pipelines failed", sync_result: result }
      end
    end

    # The active pipelines +application_token+ may publish for: every one for an
    # unrestricted token, else those of the kept softwares of its owner.
    def pipelines_for_token(application_token)
      if application_token.unrestricted?
        Pipeline.active.to_a
      else
        software_ids = Software.kept.where(
          owner_type: application_token.owner_type,
          owner_id:   application_token.owner_id
        ).pluck(:id)
        Pipeline.active.where(software_id: software_ids).to_a
      end
    end
  end
end
