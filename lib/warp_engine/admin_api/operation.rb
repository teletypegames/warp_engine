module WarpEngine
  module AdminApi
    class Operation
      PREFIX = "/api/admin/v1".freeze

      attr_reader :resource, :name, :verb, :path, :summary, :description, :query, :body,
                  :body_required, :path_params, :response, :handler, :status, :sort_columns, :default_sort

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

      def key = "#{resource.name}.#{name}"
      def read? = verb == :get
      def multipart? = @multipart
      def mcp? = @mcp && !multipart?
      def destructive? = @destructive || verb == :delete
      def idempotent? = @idempotent || %i[get put patch delete].include?(verb)

      def required_scope
        @scope || resource.scope || (read? ? Scopes::READ : Scopes::WRITE)
      end

      def route_path = "#{PREFIX}#{path}"
      def openapi_path = path.gsub(/:(\w+)/) { "{#{Regexp.last_match(1)}}" }
      def path_param_names = path.scan(/:(\w+)/).flatten

      def tool_name
        @tool_name || "#{resource.singular}_#{name}"
      end

      def path_param_schema(param)
        schema = path_params[param.to_sym] || Schema.id
        schema.respond_to?(:call) ? schema.call : schema
      end

      def inputs
        props = path_param_names.to_h { |param| [ param, path_param_schema(param) ] }
        props.merge!(query.transform_keys(&:to_s))
        props.merge!(body[:properties].transform_keys(&:to_s)) if body
        props
      end

      def required_inputs
        path_param_names + body_required
      end

      def input_schema
        Schema.object(inputs.transform_keys(&:to_sym), required: required_inputs)
      end
    end
  end
end
