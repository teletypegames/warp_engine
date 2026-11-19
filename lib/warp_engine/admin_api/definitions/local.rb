module WarpEngine
  module AdminApi
    module Definitions
      # The +local_components+ and +local_operations+ resources of
      # WarpEngine::Local: the git server and CI a local engine starts beside
      # itself, and the long operations that start them or set a software up
      # on them. Served only while the components are available (a local
      # engine with the Docker socket); elsewhere they answer 404.
      module Local
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +local_components+ and +local_operations+ resources on +api+.
        def define(api)
          available = -> { WarpEngine::Local.available? }
          api.resource(:local_components, label: "Local components", condition: available) do |r|
            components(r)
            r.action :post, "/softwares/:softwareId/local_ci", name: :setup_ci, status: 202, item: X.local_operation,
                     summary: "Set a software up on the local git server and CI (starting them when they are off); the operation's result holds pushUrl" do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              accepted(ctx, WarpEngine::LocalCiService.new.queue(software, ctx.principal.owner))
            end

            r.action :delete, "/softwares/:softwareId/local_ci", name: :teardown_ci, summary: "Stop the local CI for a software (its repository stays)" do |ctx|
              WarpEngine::LocalCiService.new.teardown(WarpEngine::Software.kept.find(ctx[:softwareId]))
              ctx.no_content
            end
          end

          api.resource(:local_operations, label: "Local operations", condition: available) do |r|
            r.get "/local_operations/:id", summary: "One local operation: its state, steps and result", item: X.local_operation do |ctx|
              ctx.ok(operation(WarpEngine::LocalOperation.find(ctx.id)))
            end
          end
        end

        # Declares the component operations on the resource +r+: list,
        # enable, disable, remove (with +purge+) and the credentials.
        def components(r)
          key = { key: -> { S.enum(WarpEngine::Local::Components.classes.map(&:key)) } }
          r.action :get, "/local_components", name: :list, many: true, item: X.local_component,
                   summary: "The components a local engine can run: git server, CI …, with their state" do |ctx|
            ctx.ok(WarpEngine::LocalComponentService.new.list.map { |line| component(line) })
          end

          { enable: "Start a component (and what it needs) and set it up", disable: "Stop a component (and what needs it); its data stays" }.each do |verb, summary|
            r.action :post, "/local_components/:key/#{verb}", name: verb, status: 202, item: X.local_operation, summary: summary,
                                                               path_params: key do |ctx|
              accepted(ctx, WarpEngine::LocalComponentService.new.queue(verb.to_s, ctx[:key]))
            end
          end

          r.action :delete, "/local_components/:key", name: :remove, status: 202, item: X.local_operation, path_params: key,
                   query: { purge: S.boolean("Remove its data and generated sign-ins too") },
                   summary: "Remove a component's containers (with purge its data too)" do |ctx|
            accepted(ctx, WarpEngine::LocalComponentService.new.queue(ctx[:purge] == true ? "purge" : "remove", ctx[:key]))
          end

          r.action :get, "/local_components/:key/credentials", name: :credentials, item: X.local_credentials, scope: Scopes::TOKENS,
                                                                path_params: key,
                   summary: "The generated sign-in of a component, to open it in a browser" do |ctx|
            record = WarpEngine::LocalComponent.find_by!(key: ctx[:key])
            ctx.ok(record.component.credentials.transform_keys(&:to_s))
          end
        end

        # The +LocalComponent+ answer of +line+ (a WarpEngine::LocalComponentService::Line).
        def component(line)
          { key: line.key, label: line.label, role: line.role, requires: line.requires, description: line.description,
            state: line.state, message: line.message }
        end

        # The +LocalOperation+ answer of +record+.
        def operation(record)
          result = record.state == "succeeded" ? record.result : nil
          { id: record.id, kind: record.kind, target: record.target, state: record.state, steps: Array(record.steps),
            result: result, error: record.error, createdAt: record.created_at, updatedAt: record.updated_at }
        end

        # A 202 answer with +record+ (a WarpEngine::LocalOperation); a 409 Error while the components are unavailable.
        def accepted(ctx, record)
          ctx.accepted(operation(record))
        rescue WarpEngine::Local::Error => e
          raise Error.conflict(e.message)
        end
      end
    end
  end
end
