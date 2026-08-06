module WarpEngine
  class CiPipelineService
    def initialize(client: WoodpeckerClient.new)
      @client = client
    end

    def dashboard
      CiRepository.active.includes(:software).map do |repo|
        pipeline = begin
          @client.latest_pipeline(repo.woodpecker_repo_id)
        rescue WoodpeckerClient::ApiError
          nil
        end

        if pipeline
          repo.update_columns(
            last_pipeline_status: pipeline["status"],
            last_pipeline_at:     pipeline["created_at"]
          )
        end

        { repo: repo, pipeline: pipeline }
      end
    end

    def trigger(repo, branch: "main")
      @client.trigger_pipeline(repo.woodpecker_repo_id, branch: branch)
    end

    def list_pipelines(repo, page: 1)
      @client.list_pipelines(repo.woodpecker_repo_id, page: page)
    end

    def pipeline_detail(repo, number)
      @client.get_pipeline(repo.woodpecker_repo_id, number)
    end
  end
end
