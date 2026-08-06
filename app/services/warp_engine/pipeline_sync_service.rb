module WarpEngine
  class PipelineSyncService
    def initialize(client: WoodpeckerClient.new)
      @client = client
    end

    def sync_all
      remote_repos = @client.list_repos
      results = { created: [], updated: [], deactivated: [] }
      remote_ids = remote_repos.map { |r| r["id"] }

      remote_repos.each do |remote|
        record = Pipeline.unscoped.find_or_initialize_by(
          woodpecker_repo_id: remote["id"]
        )

        was_new = record.new_record?
        record.assign_attributes(
          repo_name:  remote["name"],
          repo_owner: remote["owner"],
          active:     remote["active"],
          deleted_at: nil
        )

        if record.platform.blank? || record.platform == Pipeline::UNKNOWN_PLATFORM
          sw = Software.find_by(name: remote["name"])
          record.platform = sw&.platform || Pipeline::UNKNOWN_PLATFORM
          record.software = sw if sw
        end

        next unless record.save

        results[was_new ? :created : :updated] << record
      end

      Pipeline.where.not(woodpecker_repo_id: remote_ids).find_each do |orphan|
        orphan.update!(active: false) if orphan.active?
        results[:deactivated] << orphan
      end

      results
    end

    def activate(repo_id)
      @client.activate_repo(repo_id)
      sync_single(repo_id)
    end

    def deactivate(repo_id)
      @client.deactivate_repo(repo_id)
      record = Pipeline.find_by!(woodpecker_repo_id: repo_id)
      record.update!(active: false)
    end

    private

    def sync_single(repo_id)
      remote = @client.get_repo(repo_id)
      record = Pipeline.unscoped.find_or_initialize_by(woodpecker_repo_id: repo_id)
      record.assign_attributes(
        repo_name: remote["name"], repo_owner: remote["owner"],
        active: remote["active"], deleted_at: nil
      )
      if record.platform.blank?
        sw = Software.find_by(name: remote["name"])
        record.platform = sw&.platform || Pipeline::UNKNOWN_PLATFORM
        record.software = sw if sw
      end
      record.save!
      record
    end
  end
end
