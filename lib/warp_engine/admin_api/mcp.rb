module WarpEngine
  module AdminApi
    module Mcp
      INSTRUCTIONS = "The WarpEngine admin: softwares, releases and their assets, the status and category " \
                     "vocabulary, platform links, download statistics, CI pipelines and the artifact store. " \
                     "Every tool maps one Admin API operation; admin_whoami says what this token may do.".freeze

      module_function

      def available?
        return true if defined?(::MCP::Server)

        require "mcp"
        true
      rescue LoadError
        false
      end

      def ensure_available!
        return if available?

        raise ConfigurationError, "c.admin_api.mcp needs the mcp gem: add `gem \"mcp\"` to the host's Gemfile"
      end

      def operations_for(principal)
        config = AdminApi.config
        Registry.operations.select do |operation|
          operation.mcp? && !config.mcp_excluded?(operation.resource.name) && Runner.permitted?(operation, principal)
        end
      end

      def server(principal:, base_url:)
        tools = operations_for(principal).map { |operation| tool(operation, principal, base_url) }
        ::MCP::Server.new(name: "warp_engine", title: "WarpEngine Admin", version: WarpEngine::VERSION,
                          instructions: INSTRUCTIONS, tools: tools)
      end

      def tool(operation, principal, base_url)
        ::MCP::Tool.define(
          name:         operation.tool_name,
          title:        operation.summary,
          description:  description(operation),
          input_schema: operation.input_schema,
          annotations:  {
            read_only_hint:   operation.read?,
            destructive_hint: operation.destructive?,
            idempotent_hint:  operation.idempotent?,
            open_world_hint:  false
          }
        ) do |server_context: nil, **arguments|
          Mcp.call(operation, arguments, principal: principal, base_url: base_url)
        end
      end

      def call(operation, arguments, principal:, base_url:)
        result = Runner.call(operation, principal: principal, params: arguments, base_url: base_url, via: :mcp)
        response(result.payload)
      rescue Error => e
        response(e.body.merge(status: e.status).as_json, error: true)
      end

      def response(payload, error: false)
        ::MCP::Tool::Response.new([ { type: "text", text: JSON.generate(payload) } ],
                                  error: error, structured_content: payload)
      end

      def description(operation)
        [ operation.summary, operation.description,
          "#{operation.verb.to_s.upcase} #{operation.route_path}; needs #{operation.required_scope}." ]
          .compact.join("\n\n").sub("needs any.", "needs any admin token.")
      end
    end
  end
end
