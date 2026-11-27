module WarpEngine
  module AdminApi
    module Definitions
      # The +local_providers+ and +local_tasks+ resources of
      # WarpEngine::Local: the git server and CI a local engine starts beside
      # itself, and the long tasks that start them or set a software up
      # on them. Served only while the providers are available (a local
      # engine with the Docker socket); elsewhere they answer 404.
      module Local
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +local_providers+ and +local_tasks+ resources on +api+.
        def define(api)
          available = -> { WarpEngine::Local.available? }
          api.resource(:local_providers, label: "Local providers", condition: available) do |r|
            providers(r)
            r.action :post, "/softwares/:softwareId/local_ci", name: :setup_ci, status: 202, item: X.local_task,
                     summary: "Set a software up on the local git server and CI (starting them when they are off); the task's result holds pushUrl" do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              accepted(ctx, WarpEngine::LocalCiService.new.queue(software, ctx.principal.owner))
            end

            r.action :delete, "/softwares/:softwareId/local_ci", name: :teardown_ci, summary: "Stop the local CI for a software (its repository stays)" do |ctx|
              WarpEngine::LocalCiService.new.teardown(WarpEngine::Software.kept.find(ctx[:softwareId]))
              ctx.no_content
            end
          end

          api.resource(:local_tasks, label: "Local tasks", condition: available) do |r|
            r.get "/local_tasks/:id", summary: "One local task: its state, steps and result", item: X.local_task do |ctx|
              ctx.ok(task(WarpEngine::LocalTask.find(ctx.id)))
            end
          end
        end

        # Declares the provider operations on the resource +r+: list,
        # enable, disable, remove (with +purge+) and the credentials.
        def providers(r)
          key = { key: -> { S.enum(WarpEngine::Local::Providers.classes.map(&:key)) } }
          r.action :get, "/local_providers", name: :list, many: true, item: X.local_provider,
                   summary: "The providers a local engine can run: git server, CI …, with their state" do |ctx|
            ctx.ok(WarpEngine::LocalProviderService.new.list.map { |line| provider(line) })
          end

          { enable: "Start a provider (and what it needs) and set it up", disable: "Stop a provider (and what needs it); its data stays" }.each do |verb, summary|
            r.action :post, "/local_providers/:key/#{verb}", name: verb, status: 202, item: X.local_task, summary: summary,
                                                               path_params: key do |ctx|
              accepted(ctx, WarpEngine::LocalProviderService.new.queue(verb.to_s, ctx[:key]))
            end
          end

          r.action :delete, "/local_providers/:key", name: :remove, status: 202, item: X.local_task, path_params: key,
                   query: { purge: S.boolean("Remove its data and generated sign-ins too") },
                   summary: "Remove a provider's containers (with purge its data too)" do |ctx|
            accepted(ctx, WarpEngine::LocalProviderService.new.queue(ctx[:purge] == true ? "purge" : "remove", ctx[:key]))
          end

          r.action :get, "/local_providers/:key/credentials", name: :credentials, item: X.local_credentials, scope: Scopes::TOKENS,
                                                                path_params: key,
                   summary: "The generated sign-in of a provider, to open it in a browser" do |ctx|
            record = WarpEngine::LocalProvider.find_by!(key: ctx[:key])
            ctx.ok(record.provider.credentials.transform_keys(&:to_s))
          end
        end

        # The +LocalProvider+ answer of +line+ (a WarpEngine::LocalProviderService::Line).
        def provider(line)
          { key: line.key, label: line.label, role: line.role, requires: line.requires, description: line.description,
            state: line.state, message: line.message }
        end

        # The +LocalTask+ answer of +record+.
        def task(record)
          result = record.state == "succeeded" ? record.result : nil
          { id: record.id, kind: record.kind, target: record.target, state: record.state, steps: Array(record.steps),
            result: result, error: record.error, createdAt: record.created_at, updatedAt: record.updated_at }
        end

        # A 202 answer with +record+ (a WarpEngine::LocalTask); a 409 Error while the providers are unavailable.
        def accepted(ctx, record)
          ctx.accepted(task(record))
        rescue WarpEngine::Local::Error => e
          raise Error.conflict(e.message)
        end
      end
    end
  end
end
