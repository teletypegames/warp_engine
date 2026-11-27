module WarpEngine
  # Mirrors the repositories of the CI adapter into WarpEngine::CiRepository records.
  class CiRepositorySyncService
    # [ci] the CI adapter, by default WarpEngine.ci
    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    # Creates or updates (and restores) a WarpEngine::CiRepository for every CI
    # repository, linking it to the kept software of the same name and its
    # platform when the repository has none yet, and deactivates the kept repositories
    # whose repository is gone.
    #
    # Returns a Hash with the +created+, +updated+ and +deactivated+ repositories;
    # a repository that does not save is left out. Raises WarpEngine::CI::Error
    # when the CI cannot be reached.
    def sync_all
      remote_repos = @ci.repos
      results = { created: [], updated: [], deactivated: [] }
      remote_ids = remote_repos.map(&:id)

      remote_repos.each do |remote|
        record = CiRepository.find_or_initialize_by_remote_repo_id(remote.id)

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

      CiRepository.kept.where.not(woodpecker_repo_id: remote_ids).find_each do |orphan|
        orphan.update!(active: false) if orphan.active?
        results[:deactivated] << orphan
      end

      results
    end

    # Activates the CI repository +repo_id+ and syncs its record. Returns the
    # saved WarpEngine::CiRepository.
    def activate(repo_id)
      @ci.activate_repo(repo_id)
      sync_single(repo_id)
    end

    # Activates CI for the SCM repository +scm_repo_id+ the CI has not
    # seen yet (WarpEngine::CI adapter +activate_scm_repo+) and syncs its
    # record. Returns the saved WarpEngine::CiRepository.
    def activate_scm(scm_repo_id)
      remote = @ci.activate_scm_repo(scm_repo_id)
      sync_single(remote.id)
    end

    # Deactivates the CI repository +repo_id+ and marks its record inactive.
    # Raises ActiveRecord::RecordNotFound when no kept repository matches.
    def deactivate(repo_id)
      @ci.deactivate_repo(repo_id)
      record = CiRepository.kept.find_by!(woodpecker_repo_id: repo_id)
      record.update!(active: false)
    end

    private

    def sync_single(repo_id)
      remote = @ci.repo(repo_id)
      record = CiRepository.find_or_initialize_by_remote_repo_id(repo_id)
      record.assign_attributes(
        repo_name: remote.name, repo_owner: remote.owner,
        active: remote.active?, deleted_at: nil
      )
      assign_platform(record, remote.name)
      record.save!
      record
    end

    def assign_platform(record, repo_name)
      return unless record.platform.blank? || record.platform == CiRepository::UNKNOWN_PLATFORM

      sw = Software.kept.find_by(name: repo_name)
      record.platform = sw&.platform || CiRepository::UNKNOWN_PLATFORM
      record.software = sw if sw
    end
  end
end
