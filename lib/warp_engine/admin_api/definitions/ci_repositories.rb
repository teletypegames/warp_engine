module WarpEngine
  module AdminApi
    module Definitions
      # The +ci_repositories+ resource: the CI repositories (WarpEngine::CiRepository), syncing
      # them, listing and triggering their pipeline runs. Answers 503 while CI is not configured.
      module CiRepositories
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        # The answer while CI is not configured.
        UNAVAILABLE = { status: 503, message: "CI not configured" }.freeze

        module_function

        # Declares the +ci_repositories+ resource on +api+: list, <tt>POST /ci_repositories/sync</tt>,
        # get, update, <tt>GET /ci_repositories/:id/runs</tt> and <tt>POST /ci_repositories/:id/trigger</tt>
        # (409 for an inactive CI repository).
        def define(api)
          api.resource(:ci_repositories, label: "CI repositories", condition: -> { WarpEngine.ci.configured? },
                                       unavailable: UNAVAILABLE) do |r|
            r.list "/ci_repositories", summary: "The CI repositories the engine knows", item: X.ci_repository,
                   filters: { platform: S.string, active: S.boolean },
                   sort: { repoName: :repo_name, lastPipelineAt: :last_pipeline_at } do |ctx|
              scope = WarpEngine::CiRepository.kept
              scope = scope.where(platform: ctx[:platform]) if ctx[:platform].present?
              scope = scope.where(active: ctx[:active]) if ctx.key?(:active)
              ctx.list(scope, Admin::CiRepositorySerializer)
            end

            r.action :post, "/ci_repositories/sync", name: :sync, summary: "Sync the repositories from the CI server",
                     item: X.ci_repository_sync do |ctx|
              result = WarpEngine::CiRepositorySyncService.new.sync_all
              ctx.ok(result.transform_values { |records| Admin::CiRepositorySerializer.render_as_hash(records) })
            end

            r.get "/ci_repositories/:id", summary: "One CI repository", item: X.ci_repository do |ctx|
              ctx.ok(Admin::CiRepositorySerializer.render_as_hash(WarpEngine::CiRepository.kept.find(ctx.id)))
            end

            r.update "/ci_repositories/:id", summary: "Set a CI repository's platform or software", body: X.ci_repository_body,
                     item: X.ci_repository do |ctx|
              repository = WarpEngine::CiRepository.kept.find(ctx.id)
              repository.assign_attributes(ctx.attributes)
              ctx.ok(Admin::CiRepositorySerializer.render_as_hash(ctx.save!(repository)))
            end

            r.action :get, "/ci_repositories/:id/runs", name: :runs, summary: "The pipeline runs of a CI repository, newest first",
                     item: X.pipeline_run, many: true,
                     query: { page: S.integer("Page of the CI server's listing, from 1", minimum: 1) } do |ctx|
              repository = WarpEngine::CiRepository.kept.find(ctx.id)
              runs = WarpEngine::CiRepositoryService.new.runs(repository, page: [ ctx[:page].to_i, 1 ].max)
              ctx.ok(runs.map(&:as_json))
            end

            r.action :post, "/ci_repositories/:id/trigger", name: :trigger, summary: "Start a pipeline run",
                     item: X.pipeline_run, body: S.object({ branch: S.string("Default: main") }) do |ctx|
              repository = WarpEngine::CiRepository.kept.find(ctx.id)
              raise Error.conflict("#{repository.full_name} is inactive") unless repository.active

              run = WarpEngine::CiRepositoryService.new.trigger(repository, branch: ctx[:branch].presence || "main")
              ctx.ok(run.as_json)
            end
          end
        end
      end
    end
  end
end
