module WarpEngine
  module Api
    module Ci
      # Starts runs of tracked CI repositories. Needs the update credential in
      # <tt>X-Update-Secret</tt> (see WarpEngine::UpdateAuthentication).
      class PipelineRunsController < BaseController
        include WarpEngine::UpdateAuthentication

        resource_description do
          short "CI pipeline runs"
        end

        api :POST, "/api/ci/repositories/:id/trigger", "Trigger a pipeline run of a CI repository"
        header "X-Update-Secret", "Shared secret or application token (update scope)", required: true
        param :id, :number, required: true, desc: "CI repository id"
        param :branch, String, required: false, desc: "Branch to build (default: main)"
        returns code: 200, desc: "JSON with triggered run data"
        error code: 401, desc: "Invalid secret"
        error code: 503, desc: "No CI provider configured"
        # <tt>POST /api/ci/repositories/:id/trigger</tt>.
        #
        # [id]     the WarpEngine::CiRepository id
        # [branch] the branch to build, +main+ by default
        #
        # Triggers a run through WarpEngine::CiRepositoryService and renders
        # <tt>{ "triggered": true, "pipeline": ... }</tt> with the CI's run data.
        # Responds 401 without a valid update credential and 404 for an unknown
        # repository.
        def create
          unless update_authorized?(required_scope: WarpEngine::ApplicationToken::UPDATE_SCOPE)
            return render json: { error: "Unauthorized" }, status: :unauthorized
          end

          repository = ci_repository_service.find(params[:id])
          result = ci_repository_service.trigger(repository, branch: params[:branch].presence || "main")

          render json: { triggered: true, pipeline: result }
        end
      end
    end
  end
end
