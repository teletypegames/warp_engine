module WarpEngine
  class PipelineSyncService
    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    def sync_all
      remote_repos = @ci.repos
      results = { created: [], updated: [], deactivated: [] }
      remote_ids = remote_repos.map(&:id)

      remote_repos.each do |remote|
        record = Pipeline.find_or_initialize_by_remote_repo_id(remote.id)

        was_new = record.new_record?
        record.assign_attributes(
          repo_name:  remote.name,
          repo_owner: remote.owner,
          active:     remote.active?,
          deleted_at: nil
        )

        assign_platform(record, remote.name)

        next unless record.save

        results[was_new ? :created : :updated] << record
      end

      Pipeline.kept.where.not(woodpecker_repo_id: remote_ids).find_each do |orphan|
        orphan.update!(active: false) if orphan.active?
        results[:deactivated] << orphan
      end

      results
    end

    def activate(repo_id)
      @ci.activate_repo(repo_id)
      sync_single(repo_id)
    end

    def deactivate(repo_id)
      @ci.deactivate_repo(repo_id)
      record = Pipeline.kept.find_by!(woodpecker_repo_id: repo_id)
      record.update!(active: false)
    end

    private

    def sync_single(repo_id)
      remote = @ci.repo(repo_id)
      record = Pipeline.find_or_initialize_by_remote_repo_id(repo_id)
      record.assign_attributes(
        repo_name: remote.name, repo_owner: remote.owner,
        active: remote.active?, deleted_at: nil
      )
      assign_platform(record, remote.name)
      record.save!
      record
    end

    def assign_platform(record, repo_name)
      return unless record.platform.blank? || record.platform == Pipeline::UNKNOWN_PLATFORM

      sw = Software.kept.find_by(name: repo_name)
      record.platform = sw&.platform || Pipeline::UNKNOWN_PLATFORM
      record.software = sw if sw
    end
  end
end
