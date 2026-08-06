module WarpEngine
  class CiPipelineService
    def initialize(client: WoodpeckerClient.new)
      @client = client
    end

    def dashboard
      CiRepository.active.includes(:software).map do |repo|
        pipeline = begin
          @client.latest_pipeline(repo.repo_owner, repo.repo_name)
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
      @client.trigger_pipeline(repo.repo_owner, repo.repo_name, branch: branch)
    end

    def list_pipelines(repo, page: 1)
      @client.list_pipelines(repo.repo_owner, repo.repo_name, page: page)
    end

    def pipeline_detail(repo, number)
      @client.get_pipeline(repo.repo_owner, repo.repo_name, number)
    end
  end
end
