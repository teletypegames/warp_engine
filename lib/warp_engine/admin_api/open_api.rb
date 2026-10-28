module WarpEngine
  module AdminApi
    # Builds the OpenAPI 3.1 document of the Admin API from the Registry.
    module OpenApi
      # Short name of Schema.
      S = Schema

      # The error responses by status: component name and description.
      ERRORS = {
        400 => [ "BadRequest", "A parameter is missing or malformed" ],
        401 => [ "Unauthorized", "No token, or not an admin token" ],
        403 => [ "Forbidden", "The token lacks the scope this needs" ],
        404 => [ "NotFound", "No such record, or the resource is not enabled here" ],
        409 => [ "Conflict", "The request clashes with the current state" ],
        422 => [ "Unprocessable", "The record did not validate" ],
        429 => [ "TooManyRequests", "Rate limit reached; see Retry-After" ],
        502 => [ "BadGateway", "The CI server refused or failed" ],
        503 => [ "Unavailable", "The part of the engine this needs is not configured" ]
      }.freeze

      module_function

      # The OpenAPI document as a hash, listing the operations served here (see
      # #documented?), with +server_url+ as its only server.
      def document(server_url:)
        operations = Registry.operations.select { |operation| documented?(operation) }
        paths = {}
        operations.each do |operation|
          (paths[operation.openapi_path] ||= {})[operation.verb.to_s] = operation_object(operation)
        end

        {
          openapi:    "3.1.0",
          info:       {
            title:         "WarpEngine Admin API",
            version:       WarpEngine::VERSION,
            description:   "What the WarpEngine admin does, for programs: the catalog, its vocabulary, " \
                           "downloads, pipelines, the artifact store and the application tokens.",
            "x-api-version": AdminApi::VERSION
          },
          servers:    [ { url: server_url } ],
          security:   [ { bearerAuth: [] } ],
          tags:       operations.map(&:resource).uniq.map { |resource| { name: resource.label } },
          paths:      paths,
          components: components
        }
      end

      # Whether +operation+ is served here: its resource enabled and available, and not a write when read-only.
      def documented?(operation)
        config = AdminApi.config
        resource = operation.resource
        return false unless resource.always? || config.resource_enabled?(resource.name)
        return false unless resource.available?

        operation.read? || !config.read_only?
      end

      # The OpenAPI operation object of +operation+.
      def operation_object(operation)
        {
          operationId:        operation.tool_name,
          summary:            operation.summary,
          description:        operation.description,
          tags:               [ operation.resource.label ],
          "x-required-scope": operation.required_scope == :any ? nil : operation.required_scope,
          parameters:         parameters(operation).presence,
          requestBody:        request_body(operation),
          responses:          responses(operation)
        }.compact
      end

      # The OpenAPI path and query parameters of +operation+.
      def parameters(operation)
        path = operation.path_param_names.map do |name|
          { name: name, in: "path", required: true, schema: operation.path_param_schema(name) }
        end
        query = operation.query.map do |name, schema|
          { name: name.to_s, in: "query", required: operation.body_required.include?(name.to_s), schema: schema }.tap do |p|
            p.delete(:required) unless p[:required]
          end
        end
        path + query
      end

      # The OpenAPI request body of +operation+, JSON or multipart, or +nil+ without a body.
      def request_body(operation)
        body = operation.body
        return nil if body.nil?

        required = operation.body_required & body[:properties].keys.map(&:to_s)
        media = operation.multipart? ? "multipart/form-data" : "application/json"
        {
          required: required.any?,
          content:  { media => { schema: body.merge(required: required.presence).compact } }
        }
      end

      # The OpenAPI responses of +operation+: its success answer and the errors it can give.
      def responses(operation)
        success = if operation.response[:kind] == :none
          { description: "Done; no content" }
        else
          { description: "OK", content: { "application/json" => { schema: envelope(operation.response) } } }
        end

        codes = [ 400, 401, 403, 404 ]
        codes += [ 409, 422 ] unless operation.read?
        codes << 429 if AdminApi.config.rate_limit.present?
        codes += [ 502, 503 ] if operation.resource.name == :pipelines

        { operation.status.to_s => success }.merge(
          codes.to_h { |code| [ code.to_s, { "$ref": "#/components/responses/#{ERRORS[code].first}" } ] }
        )
      end

      # The schema of the <tt>{ data:, meta: }</tt> answer for a +response+ shape (page, many or one).
      def envelope(response)
        item = S.ref(response[:item].name)
        case response[:kind]
        when :page then S.object({ data: S.array(item), meta: S.ref("PageMeta") }, required: %i[data meta])
        when :many then S.object({ data: S.array(item) }, required: %i[data])
        else S.object({ data: item }, required: %i[data])
        end
      end

      # The OpenAPI components: the bearer security scheme, the schemas and the error responses.
      def components
        schemas = Definitions::Schemas.all.to_h { |named| [ named.name, named.schema ] }
        schemas["Error"] = S.object({ error: S.string, details: S.object({}, additional: S.array(S.string)) },
                                    required: %i[error])
        schemas["PageMeta"] = S.object({
          page: S.integer, perPage: S.integer, total: S.integer, totalPages: S.integer,
          nextPage: S.nullable(S.integer)
        })

        {
          securitySchemes: {
            bearerAuth: {
              type:        "http",
              scheme:      "bearer",
              description: "An application token with admin scopes: #{Scopes::ALL.join(', ')}. " \
                           "Every operation names the one it needs in x-required-scope."
            }
          },
          schemas:         schemas,
          responses:       ERRORS.values.to_h do |name, description|
            [ name, { description: description, content: { "application/json" => { schema: S.ref("Error") } } } ]
          end
        }
      end
    end
  end
end
