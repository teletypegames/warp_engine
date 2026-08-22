module WarpEngine
  class PipelineService
    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    def trigger(pipeline, branch: "main")
      @ci.trigger(pipeline.remote_repo_id, branch: branch)
    end

    def runs(pipeline, page: 1)
      runs = @ci.runs(pipeline.remote_repo_id, page: page)
      refresh_last_run(pipeline, runs.first) if page == 1
      runs
    end

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
