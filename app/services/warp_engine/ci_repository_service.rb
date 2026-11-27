module WarpEngine
  # Triggers and lists the CI runs of a WarpEngine::CiRepository through the CI adapter.
  class CiRepositoryService
    # [ci] the CI adapter, by default WarpEngine.ci
    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    # Returns the active repositories with their softwares, as
    # <tt>GET /api/ci/repositories</tt> lists them.
    def active = WarpEngine::CiRepository.active.includes(:software)

    # Returns the kept repository with the id +id+. Raises
    # ActiveRecord::RecordNotFound when there is none.
    def find(id) = WarpEngine::CiRepository.kept.find(id)

    # Starts a run of +repository+ on +branch+. Returns what the CI adapter answers.
    def trigger(repository, branch: "main")
      @ci.trigger(repository.remote_repo_id, branch: branch)
    end

    # Returns the page +page+ of the runs of +repository+, newest first. The first
    # page also stores the newest run's status and time on the repository.
    def runs(repository, page: 1)
      runs = @ci.runs(repository.remote_repo_id, page: page)
      refresh_last_run(repository, runs.first) if page == 1
      runs
    end

    # Returns the run +number+ of +repository+.
    def run(repository, number)
      @ci.run(repository.remote_repo_id, number)
    end

    private

    def refresh_last_run(repository, run)
      return unless run && repository.persisted?

      repository.update_columns(
        last_pipeline_status: run.status,
        last_pipeline_at:     run.created_at
      )
    end
  end
end
