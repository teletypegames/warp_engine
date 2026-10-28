module WarpEngine
  # Triggers and lists the CI runs of a WarpEngine::Pipeline through the CI adapter.
  class PipelineService
    # [ci] the CI adapter, by default WarpEngine.ci
    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    # Starts a run of +pipeline+ on +branch+. Returns what the CI adapter answers.
    def trigger(pipeline, branch: "main")
      @ci.trigger(pipeline.remote_repo_id, branch: branch)
    end

    # Returns the page +page+ of the runs of +pipeline+, newest first. The first
    # page also stores the newest run's status and time on the pipeline.
    def runs(pipeline, page: 1)
      runs = @ci.runs(pipeline.remote_repo_id, page: page)
      refresh_last_run(pipeline, runs.first) if page == 1
      runs
    end

    # Returns the run +number+ of +pipeline+.
    def run(pipeline, number)
      @ci.run(pipeline.remote_repo_id, number)
    end

    private

    def refresh_last_run(pipeline, run)
      return unless run && pipeline.persisted?

      pipeline.update_columns(
        last_pipeline_status: run.status,
        last_pipeline_at:     run.created_at
      )
    end
  end
end
