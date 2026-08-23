module WarpEngine
  module Api
    module Ci
      class PipelinesController < BaseController
        resource_description do
          short "CI pipelines"
        end

        api :GET, "/api/ci/pipelines", "List active pipelines"
        returns code: 200, desc: "JSON array of tracked pipelines"
        error code: 503, desc: "No CI provider configured"
        def index
          pipelines = pipeline_scope.active.includes(:software)
          render json: WarpEngine::PipelineSerializer.render_as_hash(pipelines)
        end

        api :GET, "/api/ci/pipelines/:id/status", "Get a pipeline with its latest run"
        param :id, :number, required: true, desc: "Pipeline id"
        returns code: 200, desc: "JSON with pipeline and latest run data"
        error code: 503, desc: "No CI provider configured"
        def show
          pipeline = pipeline_scope.find(params[:id])

          render json: {
            pipeline:   WarpEngine::PipelineSerializer.render_as_hash(pipeline),
            latest_run: latest_run(pipeline)
          }
        end

        private

        def latest_run(pipeline)
          WarpEngine::PipelineService.new.run(pipeline, "latest")
        rescue WarpEngine::CI::Error
          nil
        end
      end
    end
  end
end
