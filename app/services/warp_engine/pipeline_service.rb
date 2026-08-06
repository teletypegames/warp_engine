module WarpEngine
  class PipelineService
    def initialize(client: WoodpeckerClient.new)
      @client = client
    end

    def trigger(pipeline, branch: "main")
      @client.trigger_pipeline(pipeline.woodpecker_repo_id, branch: branch)
    end

    # Fetches one page of a pipeline's runs; the newest one refreshes the
    # cached last_pipeline_* columns (Pipelines index and the CI API).
    def list_pipelines(pipeline, page: 1)
      runs = @client.list_pipelines(pipeline.woodpecker_repo_id, page: page)
      refresh_last_pipeline(pipeline, runs.first) if page == 1 && runs.is_a?(Array)
      runs
    end

    def pipeline_detail(pipeline, number)
      @client.get_pipeline(pipeline.woodpecker_repo_id, number)
    end

    private

    # Woodpecker returns unix epoch seconds in "created".
    def refresh_last_pipeline(pipeline, run)
      return unless run && pipeline.persisted?

      pipeline.update_columns(
        last_pipeline_status: run["status"],
        last_pipeline_at:     run["created"] ? Time.zone.at(run["created"]) : nil
      )
    end
  end
end
