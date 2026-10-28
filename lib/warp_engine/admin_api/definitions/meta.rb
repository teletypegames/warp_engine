module WarpEngine
  module AdminApi
    module Definitions
      # The +meta+ resource: <tt>GET /me</tt> (MCP tool +admin_whoami+), open to any admin caller.
      module Meta
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +meta+ resource on the Registry::Builder +api+.
        def define(api)
          api.resource(:meta, label: "Meta", scope: :any, always: true) do |r|
            r.get "/me", name: :whoami, tool_name: "admin_whoami",
                  summary: "Who is calling, with which scopes, and what they may use here", item: X.principal do |ctx|
              ctx.ok(principal_payload(ctx.principal))
            end
          end
        end

        # The <tt>GET /me</tt> answer for +principal+: Principal#as_json plus the
        # resources it may use, whether the Admin API is read-only and whether MCP is on.
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
