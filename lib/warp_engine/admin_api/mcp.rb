module WarpEngine
  module AdminApi
    # The Admin API as an MCP server: every Operation the caller may run becomes a
    # tool. Needs the +mcp+ gem in the host's Gemfile.
    module Mcp
      # The instructions the MCP server gives the client.
      INSTRUCTIONS = "The WarpEngine admin: softwares, releases and their assets, the status and category " \
                     "vocabulary, platform links, download statistics, CI pipelines and the artifact store. " \
                     "Every tool maps one Admin API operation; admin_whoami says what this token may do.".freeze

      module_function

      # Whether the +mcp+ gem is loaded or loadable; requires it when needed.
      def available?
        return true if defined?(::MCP::Server)

        require "mcp"
        true
      rescue LoadError
        false
      end

      # Raises ConfigurationError unless #available?.
      def ensure_available!
        return if available?

        raise ConfigurationError, "c.admin_api.mcp needs the mcp gem: add `gem \"mcp\"` to the host's Gemfile"
      end

      # The operations offered as tools to +principal+: MCP-enabled, not excluded, permitted.
      def operations_for(principal)
        config = AdminApi.config
        Registry.operations.select do |operation|
          operation.mcp? && !config.mcp_excluded?(operation.resource.name) && Runner.permitted?(operation, principal)
        end
      end

      # Builds an <tt>MCP::Server</tt> with the tools of +principal+, whose calls see +base_url+.
      def server(principal:, base_url:)
        tools = operations_for(principal).map { |operation| tool(operation, principal, base_url) }
        ::MCP::Server.new(name: "warp_engine", title: "WarpEngine Admin", version: WarpEngine::VERSION,
                          instructions: INSTRUCTIONS, tools: tools)
      end

      # Defines the <tt>MCP::Tool</tt> of +operation+, run as +principal+, with MCP hints from the operation.
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

      # Runs +operation+ with +arguments+ through Runner and returns its tool
      # response; an Error becomes an error response carrying its body and status.
      def call(operation, arguments, principal:, base_url:)
        result = Runner.call(operation, principal: principal, params: arguments, base_url: base_url, via: :mcp)
        response(result.payload)
      rescue Error => e
        response(e.body.merge(status: e.status).as_json, error: true)
      end

      # An <tt>MCP::Tool::Response</tt> with +payload+ as JSON text and structured content.
      def response(payload, error: false)
        ::MCP::Tool::Response.new([ { type: "text", text: JSON.generate(payload) } ],
                                  error: error, structured_content: payload)
      end

      # The tool description of +operation+: summary, description, route and needed scope.
      def description(operation)
        [ operation.summary, operation.description,
          "#{operation.verb.to_s.upcase} #{operation.route_path}; needs #{operation.required_scope}." ]
          .compact.join("\n\n").sub("needs any.", "needs any admin token.")
      end
    end
  end
end
