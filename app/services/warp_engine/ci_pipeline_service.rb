module WarpEngine
  class CiPipelineService
    def initialize(client: WoodpeckerClient.new)
      @client = client
    end

    def trigger(repo, branch: "main")
      @client.trigger_pipeline(repo.woodpecker_repo_id, branch: branch)
    end

    # Fetches one page of a repo's pipelines; the newest one refreshes the
    # repo's cached last_pipeline_* columns (CI Repos index and the CI API).
    def list_pipelines(repo, page: 1)
      pipelines = @client.list_pipelines(repo.woodpecker_repo_id, page: page)
      refresh_last_pipeline(repo, pipelines.first) if page == 1 && pipelines.is_a?(Array)
      pipelines
    end

    def pipeline_detail(repo, number)
      @client.get_pipeline(repo.woodpecker_repo_id, number)
    end

    private

    # Woodpecker returns unix epoch seconds in "created".
    def refresh_last_pipeline(repo, pipeline)
      return unless pipeline && repo.persisted?

      repo.update_columns(
        last_pipeline_status: pipeline["status"],
        last_pipeline_at:     pipeline["created"] ? Time.zone.at(pipeline["created"]) : nil
      )
    end
  end
end
