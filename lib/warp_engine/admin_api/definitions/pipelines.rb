module WarpEngine
  module AdminApi
    module Definitions
      # The +pipelines+ resource: the CI repositories (WarpEngine::Pipeline), syncing
      # them, listing and triggering runs. Answers 503 while CI is not configured.
      module Pipelines
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        # The answer while CI is not configured.
        UNAVAILABLE = { status: 503, message: "CI not configured" }.freeze

        module_function

        # Declares the +pipelines+ resource on +api+: list, <tt>POST /pipelines/sync</tt>,
        # get, update, <tt>GET /pipelines/:id/runs</tt> and <tt>POST /pipelines/:id/trigger</tt>
        # (409 for an inactive pipeline).
        def define(api)
          api.resource(:pipelines, label: "Pipelines", condition: -> { WarpEngine.ci.configured? },
                                   unavailable: UNAVAILABLE) do |r|
            r.list "/pipelines", summary: "The CI repositories the engine knows", item: X.pipeline,
                   filters: { platform: S.string, active: S.boolean },
                   sort: { repoName: :repo_name, lastPipelineAt: :last_pipeline_at } do |ctx|
              scope = WarpEngine::Pipeline.kept
              scope = scope.where(platform: ctx[:platform]) if ctx[:platform].present?
              scope = scope.where(active: ctx[:active]) if ctx.key?(:active)
              ctx.list(scope, Admin::PipelineSerializer)
            end

            r.action :post, "/pipelines/sync", name: :sync, summary: "Sync the repositories from the CI server",
                     item: X.pipeline_sync do |ctx|
              result = WarpEngine::PipelineSyncService.new.sync_all
              ctx.ok(result.transform_values { |records| Admin::PipelineSerializer.render_as_hash(records) })
            end

            r.get "/pipelines/:id", summary: "One pipeline", item: X.pipeline do |ctx|
              ctx.ok(Admin::PipelineSerializer.render_as_hash(WarpEngine::Pipeline.kept.find(ctx.id)))
            end

            r.update "/pipelines/:id", summary: "Set a pipeline's platform or software", body: X.pipeline_body,
                     item: X.pipeline do |ctx|
              pipeline = WarpEngine::Pipeline.kept.find(ctx.id)
              pipeline.assign_attributes(ctx.attributes)
              ctx.ok(Admin::PipelineSerializer.render_as_hash(ctx.save!(pipeline)))
            end

            r.action :get, "/pipelines/:id/runs", name: :runs, summary: "The runs of a pipeline, newest first",
                     item: X.pipeline_run, many: true,
                     query: { page: S.integer("Page of the CI server's listing, from 1", minimum: 1) } do |ctx|
              pipeline = WarpEngine::Pipeline.kept.find(ctx.id)
              runs = WarpEngine::PipelineService.new.runs(pipeline, page: [ ctx[:page].to_i, 1 ].max)
              ctx.ok(runs.map(&:as_json))
            end

            r.action :post, "/pipelines/:id/trigger", name: :trigger, summary: "Start a pipeline run",
                     item: X.pipeline_run, body: S.object({ branch: S.string("Default: main") }) do |ctx|
              pipeline = WarpEngine::Pipeline.kept.find(ctx.id)
              raise Error.conflict("#{pipeline.full_name} is inactive") unless pipeline.active

              run = WarpEngine::PipelineService.new.trigger(pipeline, branch: ctx[:branch].presence || "main")
              ctx.ok(run.as_json)
            end
          end
        end
      end
    end
  end
end
