module WarpEngine
  module AdminApi
    module Definitions
      module Meta
        X = Schemas

        module_function

        def define(api)
          api.resource(:meta, label: "Meta", scope: :any, always: true) do |r|
            r.get "/me", name: :whoami, tool_name: "admin_whoami",
                  summary: "Who is calling, with which scopes, and what they may use here", item: X.principal do |ctx|
              ctx.ok(principal_payload(ctx.principal))
            end
          end
        end

        def principal_payload(principal)
          config = AdminApi.config
          usable = Registry.resources.reject(&:always?).select do |resource|
            resource.operations.any? { |operation| Runner.permitted?(operation, principal) }
          end
          principal.as_json.merge(
            resources: usable.map { |resource| resource.name.to_s },
            readOnly:  config.read_only?,
            mcp:       config.mcp?
          )
        end
      end
    end
  end
end
