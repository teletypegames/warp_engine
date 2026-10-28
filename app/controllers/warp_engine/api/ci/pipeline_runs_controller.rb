module WarpEngine
  module Api
    module Ci
      # Starts runs of tracked CI pipelines. Needs the update credential in
      # <tt>X-Update-Secret</tt> (see WarpEngine::UpdateAuthentication).
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
        # <tt>POST /api/ci/pipelines/:id/trigger</tt>.
        #
        # [id]     the WarpEngine::Pipeline id
        # [branch] the branch to build, +main+ by default
        #
        # Triggers a run through WarpEngine::PipelineService and renders
        # <tt>{ "triggered": true, "pipeline": ... }</tt> with the CI's run data.
        # Responds 401 without a valid update credential and 404 for an unknown
        # pipeline.
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
