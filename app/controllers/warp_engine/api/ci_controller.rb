module WarpEngine
  module Api
    class CiController < ApiController
      include UpdateAuthentication

      before_action :require_woodpecker!

      resource_description do
        short "CI repository and pipeline management"
      end

      api :GET, "/api/ci/repos", "List active CI repositories"
      returns code: 200, desc: "JSON array of tracked repos"
      error code: 503, desc: "Woodpecker not configured"
      def repos
        records = CiRepository.active.includes(:software)
        render json: records.map { |r| repo_json(r) }
      end

      api :GET, "/api/ci/repos/:id/status", "Get a CI repository with its latest pipeline"
      param :id, :number, required: true, desc: "CiRepository id"
      returns code: 200, desc: "JSON with repo and pipeline data"
      error code: 503, desc: "Woodpecker not configured"
      def status
        repo = CiRepository.find(params[:id])
        pipeline = begin
          CiPipelineService.new.pipeline_detail(repo, "latest")
        rescue WoodpeckerClient::ApiError
          nil
        end
        render json: { repo: repo_json(repo), pipeline: pipeline }
      end

      api :POST, "/api/ci/repos/:id/trigger", "Trigger a pipeline for a CI repository"
      header "X-Update-Secret", "Shared secret or application token (update scope)", required: true
      param :id, :number, required: true, desc: "CiRepository id"
      param :branch, String, required: false, desc: "Branch to build (default: main)"
      returns code: 200, desc: "JSON with triggered pipeline data"
      error code: 401, desc: "Invalid secret"
      error code: 503, desc: "Woodpecker not configured"
      def trigger
        unless update_authorized?(required_scope: ApplicationToken::UPDATE_SCOPE)
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end

        repo = CiRepository.find(params[:id])
        result = CiPipelineService.new.trigger(repo, branch: params[:branch] || "main")
        render json: { triggered: true, pipeline: result }
      end

      private

      def require_woodpecker!
        return if WarpEngine.woodpecker_configured?

        render json: { error: "Woodpecker not configured" }, status: :service_unavailable
      end

      def repo_json(repo)
        {
          id: repo.id,
          woodpecker_repo_id: repo.woodpecker_repo_id,
          repo_owner: repo.repo_owner,
          repo_name: repo.repo_name,
          platform: repo.platform,
          active: repo.active,
          software_name: repo.software&.name,
          last_pipeline_status: repo.last_pipeline_status,
          last_pipeline_at: repo.last_pipeline_at
        }
      end
    end
  end
end
