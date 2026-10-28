module WarpEngine
  module AdminApi
    # One Admin API operation: an HTTP route, an MCP tool and an OpenAPI operation
    # at once. Declared through Resource; run by Runner.
    class Operation
      # The URL prefix of every operation route.
      PREFIX = "/api/admin/v1".freeze

      # The declaration: owning Resource, name, HTTP verb, path (with <tt>:param</tt>
      # segments), summary, description, query and body schemas, required body
      # fields, path param schemas, response shape (<tt>{ kind:, item: }</tt>),
      # handler, success status, sort key to column map and default sort key.
      attr_reader :resource, :name, :verb, :path, :summary, :description, :query, :body,
                  :body_required, :path_params, :response, :handler, :status, :sort_columns, :default_sort

      # Takes the declaration as keywords; besides the readers' values:
      #
      # [multipart]   the body is multipart form data (not offered over MCP)
      # [mcp]         offer it as an MCP tool
      # [destructive] mark it destructive for MCP (deletes always are)
      # [idempotent]  mark it idempotent for MCP (GET, PUT, PATCH, DELETE always are)
      # [scope]       the scope it needs, overriding the resource's
      # [tool_name]   the MCP tool name, overriding the default
      def initialize(resource:, name:, verb:, path:, summary:, handler:, description: nil, query: {},
                     body: nil, body_required: [], path_params: {}, response: { kind: :none },
                     status: 200, multipart: false, mcp: true, destructive: false, idempotent: false,
                     scope: nil, tool_name: nil, sort: {}, default_sort: nil)
        @resource      = resource
        @name          = name.to_sym
        @verb          = verb.to_sym
        @path          = path
        @summary       = summary
        @description   = description
        @handler       = handler
        @query         = query
        @body          = body
        @body_required = body_required.map(&:to_s)
        @path_params   = path_params
        @response      = response
        @status        = status
        @multipart     = multipart
        @mcp           = mcp
        @destructive   = destructive
        @idempotent    = idempotent
        @scope         = scope
        @tool_name     = tool_name
        @sort_columns  = sort.transform_keys(&:to_s)
        @default_sort  = default_sort
      end

      # The unique key: <tt>resource.name</tt>, a dot, then #name.
      def key = "#{resource.name}.#{name}"
      # Whether it is a GET.
      def read? = verb == :get
      # Whether the body is multipart form data.
      def multipart? = @multipart
      # Whether it is offered as an MCP tool.
      def mcp? = @mcp && !multipart?
      # Whether it destroys data.
      def destructive? = @destructive || verb == :delete
      # Whether repeating it changes nothing further.
      def idempotent? = @idempotent || %i[get put patch delete].include?(verb)

      # The scope the caller needs: its own, the resource's, or Scopes::READ for reads
      # and Scopes::WRITE for writes. <tt>:any</tt> means any admin caller.
      def required_scope
        @scope || resource.scope || (read? ? Scopes::READ : Scopes::WRITE)
      end

      # The full route path, with PREFIX.
      def route_path = "#{PREFIX}#{path}"
      # The path with <tt>{param}</tt> segments, as OpenAPI writes it.
      def openapi_path = path.gsub(/:(\w+)/) { "{#{Regexp.last_match(1)}}" }
      # The names of the path params.
      def path_param_names = path.scan(/:(\w+)/).flatten

      # The MCP tool name and OpenAPI operationId: its own, or <tt>singular_name</tt>.
      def tool_name
        @tool_name || "#{resource.singular}_#{name}"
      end

      # The schema of path param +param+, an id by default.
      def path_param_schema(param)
        schema = path_params[param.to_sym] || Schema.id
        schema.respond_to?(:call) ? schema.call : schema
      end

      # Every input schema by name: path params, query params and body properties.
      def inputs
        props = path_param_names.to_h { |param| [ param, path_param_schema(param) ] }
        props.merge!(query.transform_keys(&:to_s))
        props.merge!(body[:properties].transform_keys(&:to_s)) if body
        props
      end

      # The names of the required inputs: the path params and the required body fields.
      def required_inputs
        path_param_names + body_required
      end

      # The JSON schema object of all #inputs, the MCP tool input schema.
      def input_schema
        Schema.object(inputs.transform_keys(&:to_sym), required: required_inputs)
      end
    end
  end
end
