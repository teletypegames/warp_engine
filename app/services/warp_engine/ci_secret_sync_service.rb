module WarpEngine
  class CiSecretSyncService
    SECRET_NAME = "application_token".freeze

    def initialize(client: WoodpeckerClient.new)
      @client = client
    end

    def provision(plain_token, repos:)
      results = { synced: [], failed: [] }

      repos.each do |repo|
        if secret_exists?(repo.woodpecker_repo_id)
          @client.update_secret(repo.woodpecker_repo_id, SECRET_NAME, value: plain_token)
        else
          @client.create_secret(repo.woodpecker_repo_id, name: SECRET_NAME, value: plain_token)
        end
        results[:synced] << repo
      rescue WoodpeckerClient::ApiError, WoodpeckerClient::ConnectionError => e
        Rails.logger.error("[CiSecretSyncService] failed for #{repo.full_name}: #{e.message}")
        results[:failed] << { repo: repo, error: e.message }
      end

      results
    end

    def deprovision(application_token)
      repos_for_token(application_token).each do |repo|
        @client.delete_secret(repo.woodpecker_repo_id, SECRET_NAME)
      rescue WoodpeckerClient::ApiError => e
        Rails.logger.warn("[CiSecretSyncService] delete failed for #{repo.full_name}: #{e.message}")
      end
    end

    def rotate(application_token)
      repos = repos_for_token(application_token)
      return { rotated: false, reason: "no repos" } if repos.empty?

      new_token = ApplicationToken.create!(
        name:         "#{application_token.name} (rotated #{Date.current})",
        owner_id:     application_token.owner_id,
        owner_type:   application_token.owner_type,
        scopes:       application_token.scopes,
        expires_at:   application_token.expires_at,
        unrestricted: application_token.unrestricted?
      )

      result = provision(new_token.plain_token, repos: repos)

      if result[:synced].any?
        application_token.revoke!
        { rotated: true, new_token: new_token, sync_result: result }
      else
        new_token.revoke!
        { rotated: false, reason: "all repos failed", sync_result: result }
      end
    end

    def repos_for_token(application_token)
      if application_token.unrestricted?
        CiRepository.active.to_a
      else
        software_ids = Software.where(
          owner_type: application_token.owner_type,
          owner_id:   application_token.owner_id
        ).pluck(:id)
        CiRepository.active.where(software_id: software_ids).to_a
      end
    end

    private

    def secret_exists?(repo_id)
      secrets = @client.list_secrets(repo_id)
      secrets.any? { |s| s["name"] == SECRET_NAME }
    rescue WoodpeckerClient::ApiError
      false
    end
  end
end
