module WarpEngine
  module Api
    class CiController < ApiController
      include UpdateAuthentication

      before_action :require_ci!

      resource_description do
        short "CI pipeline management"
      end

      api :GET, "/api/ci/pipelines", "List active pipelines"
      returns code: 200, desc: "JSON array of tracked pipelines"
      error code: 503, desc: "No CI provider configured"
      def pipelines
        records = Pipeline.active.includes(:software)
        render json: records.map { |p| pipeline_json(p) }
      end

      api :GET, "/api/ci/pipelines/:id/status", "Get a pipeline with its latest run"
      param :id, :number, required: true, desc: "Pipeline id"
      returns code: 200, desc: "JSON with pipeline and latest run data"
      error code: 503, desc: "No CI provider configured"
      def status
        pipeline = Pipeline.find(params[:id])
        latest_run = begin
          PipelineService.new.run(pipeline, "latest")
        rescue CI::Error
          nil
        end
        render json: { pipeline: pipeline_json(pipeline), latest_run: latest_run }
      end

      api :POST, "/api/ci/pipelines/:id/trigger", "Trigger a pipeline"
      header "X-Update-Secret", "Shared secret or application token (update scope)", required: true
      param :id, :number, required: true, desc: "Pipeline id"
      param :branch, String, required: false, desc: "Branch to build (default: main)"
      returns code: 200, desc: "JSON with triggered run data"
      error code: 401, desc: "Invalid secret"
      error code: 503, desc: "No CI provider configured"
      def trigger
        unless update_authorized?(required_scope: ApplicationToken::UPDATE_SCOPE)
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end

        pipeline = Pipeline.find(params[:id])
        result = PipelineService.new.trigger(pipeline, branch: params[:branch] || "main")
        render json: { triggered: true, pipeline: result }
      end

      private

      def require_ci!
        return if WarpEngine.ci.configured?

        render json: { error: "CI not configured" }, status: :service_unavailable
      end

      def pipeline_json(pipeline)
        {
          id: pipeline.id,
          repo_id: pipeline.remote_repo_id,
          woodpecker_repo_id: pipeline.remote_repo_id,
          repo_owner: pipeline.repo_owner,
          repo_name: pipeline.repo_name,
          platform: pipeline.platform,
          active: pipeline.active,
          software_name: pipeline.software&.name,
          last_pipeline_status: pipeline.last_pipeline_status,
          last_pipeline_at: pipeline.last_pipeline_at
        }
      end
    end
  end
end
