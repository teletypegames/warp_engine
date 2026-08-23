module WarpEngine
  module Api
    module Ci
      class PipelineRunsController < BaseController
        include WarpEngine::UpdateAuthentication

        resource_description do
          short "CI pipeline runs"
        end

        api :POST, "/api/ci/pipelines/:id/trigger", "Trigger a pipeline"
        header "X-Update-Secret", "Shared secret or application token (update scope)", required: true
        param :id, :number, required: true, desc: "Pipeline id"
        param :branch, String, required: false, desc: "Branch to build (default: main)"
        returns code: 200, desc: "JSON with triggered run data"
        error code: 401, desc: "Invalid secret"
        error code: 503, desc: "No CI provider configured"
        def create
          unless update_authorized?(required_scope: WarpEngine::ApplicationToken::UPDATE_SCOPE)
            return render json: { error: "Unauthorized" }, status: :unauthorized
          end

          pipeline = pipeline_scope.find(params[:id])
          result = WarpEngine::PipelineService.new.trigger(pipeline, branch: params[:branch].presence || "main")

          render json: { triggered: true, pipeline: result }
        end
      end
    end
  end
end
