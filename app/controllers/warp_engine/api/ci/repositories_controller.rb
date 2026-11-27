module WarpEngine
  module Api
    module Ci
      # Lists the tracked CI repositories and reports their latest run.
      class RepositoriesController < BaseController
        resource_description do
          short "CI repositories"
        end

        api :GET, "/api/ci/repositories", "List active repositories"
        returns code: 200, desc: "JSON array of tracked repositories"
        error code: 503, desc: "No CI provider configured"
        # <tt>GET /api/ci/repositories</tt>.
        #
        # Renders the active repositories as a JSON array through
        # WarpEngine::CiRepositorySerializer.
        def index
          repositories = ci_repository_service.active
          render json: WarpEngine::CiRepositorySerializer.render_as_hash(repositories)
        end

        api :GET, "/api/ci/repositories/:id/status", "Get a repository with its latest run"
        param :id, :number, required: true, desc: "CI repository id"
        returns code: 200, desc: "JSON with repository and latest run data"
        error code: 503, desc: "No CI provider configured"
        # <tt>GET /api/ci/repositories/:id/status</tt>.
        #
        # Renders <tt>{ "pipeline": ..., "latestRun": ... }</tt>: the repository and
        # its latest run as the CI reports it, +latestRun+ being +null+ when the CI
        # call fails. Responds 404 for an unknown repository.
        def show
          repository = ci_repository_service.find(params[:id])

          render json: {
            pipeline:  WarpEngine::CiRepositorySerializer.render_as_hash(repository),
            latestRun: latest_run(repository)
          }
        end

        private

        def latest_run(repository)
          ci_repository_service.run(repository, "latest")
        rescue WarpEngine::CI::Error
          nil
        end
      end
    end
  end
end
