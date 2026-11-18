require "json"

module WarpEngine
  # The Admin API reference the SysInfo admin page draws with its own
  # template: the OpenAPI document (WarpEngine::AdminApi::OpenApi.document)
  # read into groups of operations, their parameters, request bodies and
  # responses, and the component schemas they refer to. References are
  # resolved into type names that link to the schema; nested inline objects
  # are flattened into dotted field names.
  class ApiReference
    # The HTTP methods in the order an operation list shows them.
    METHODS = %w[get post put patch delete].freeze

    # How deep inline objects are flattened before they show as +object+.
    MAX_DEPTH = 3

    # One field of a parameter list, a request body, a response or a schema:
    # its +name+ (dotted for nested fields, <tt>[]</tt> for array items),
    # where it goes (+location+: path, query or +nil+), its +type+ label, the
    # +ref+ schema name the type links to (or +nil+), whether it is
    # +required+ and +nullable+, its +description+ and +notes+ (enum values,
    # format, bounds).
    Field = ::Data.define(:name, :location, :type, :ref, :required, :nullable, :description, :notes)

    # One response of an operation: its +status+, +description+, the
    # +fields+ of its body and the +ref+ of a shared error body (or +nil+).
    Response = ::Data.define(:status, :description, :fields, :ref) do
      # Whether the status is 2xx.
      def success? = status.to_s.start_with?("2")
    end

    # One operation: +verb+, +path+, +summary+, +description+, the +scope+ it
    # needs (or +nil+), its +parameters+ and +body+ fields, the +media+ type
    # of the body, its +responses+, an +anchor+ id and a sample +curl+ line
    # (with the required body fields only).
    Operation = ::Data.define(:verb, :path, :summary, :description, :scope, :parameters, :body, :media, :responses,
                              :anchor, :curl) do
      # Returns the text the page's filter searches.
      def search_text = [ verb, path, summary, description, scope ].compact.join(" ").downcase
    end

    # The operations of one tag: its +name+ and +operations+.
    Group = ::Data.define(:name, :operations)

    # A component schema: its +name+, +anchor+ id, +description+ and +fields+.
    SchemaEntry = ::Data.define(:name, :anchor, :description, :fields)

    # [document] the OpenAPI document as a Hash (symbol or string keys)
    def initialize(document)
      @doc = JSON.parse(document.to_json)
    end

    # Returns the document's title.
    def title = @doc.dig("info", "title").to_s

    # Returns the engine version the document describes.
    def version = @doc.dig("info", "version").to_s

    # Returns the document's description.
    def description = @doc.dig("info", "description").to_s

    # Returns the base URL every path hangs on.
    def server_url = Array(@doc["servers"]).first&.dig("url").to_s

    # Returns how a caller authenticates, from the bearer security scheme.
    def auth = @doc.dig("components", "securitySchemes", "bearerAuth", "description").to_s

    # Returns the Group list, in the document's tag order, each with its
    # operations by path and then METHODS order.
    def groups
      @groups ||= begin
        operations = @doc.fetch("paths", {}).flat_map do |path, verbs|
          verbs.sort_by { |verb, _| METHODS.index(verb) || METHODS.size }.map { |verb, op| [ op, operation(path, verb, op) ] }
        end
        names = Array(@doc["tags"]).map { |tag| tag["name"] }
        names.map do |name|
          Group.new(name: name, operations: operations.select { |op, _| Array(op["tags"]).include?(name) }.map(&:last))
        end.reject { |group| group.operations.empty? }
      end
    end

    # Returns how many operations the document has.
    def operation_count = groups.sum { |group| group.operations.size }

    # Returns the SchemaEntry list of the component schemas, by name.
    def schemas
      @schemas ||= @doc.dig("components", "schemas").to_h.sort.map do |name, schema|
        SchemaEntry.new(name: name, anchor: self.class.schema_anchor(name), description: schema["description"],
                        fields: fields(schema))
      end
    end

    # Returns the anchor id of the schema +name+.
    def self.schema_anchor(name) = "we-ar-schema-#{name.to_s.parameterize}"

    private

    def operation(path, verb, op)
      parameters = Array(op["parameters"]).map do |param|
        schema = param["schema"] || {}
        Field.new(name: param["name"], location: param["in"], type: type_label(schema), ref: ref_name(schema),
                  required: param["required"] == true, nullable: nullable?(schema),
                  description: param["description"].presence || schema["description"], notes: notes(schema))
      end
      media, body_schema = op.dig("requestBody", "content")&.first
      body = body_schema ? fields(body_schema["schema"] || {}) : []
      Operation.new(verb: verb, path: path, summary: op["summary"], description: op["description"],
                    scope: op["x-required-scope"], parameters: parameters, body: body, media: media,
                    responses: responses(op), anchor: "we-ar-op-#{op['operationId'] || "#{verb}-#{path}".parameterize}",
                    curl: curl(verb, path, media, body))
    end

    def responses(op)
      op.fetch("responses", {}).map do |status, response|
        if (shared = response["$ref"])
          name = shared.split("/").last
          resolved = @doc.dig("components", "responses", name) || {}
          Response.new(status: status, description: resolved["description"].to_s,
                       fields: [], ref: ref_name(resolved.dig("content", "application/json", "schema") || {}))
        else
          schema = response.dig("content", "application/json", "schema")
          Response.new(status: status, description: response["description"].to_s,
                       fields: schema ? fields(schema) : [], ref: nil)
        end
      end
    end

    def fields(schema, prefix = nil, depth = 0)
      return [] unless schema["type"].to_s.include?("object") || schema["properties"]

      required = Array(schema["required"])
      schema.fetch("properties", {}).flat_map do |name, property|
        full = [ prefix, name ].compact.join(".")
        field = Field.new(name: full, location: nil, type: type_label(property), ref: ref_name(property),
                          required: required.include?(name), nullable: nullable?(property),
                          description: property["description"], notes: notes(property))
        [ field ] + nested(property, full, depth)
      end
    end

    def nested(property, name, depth)
      return [] if depth >= MAX_DEPTH

      if inline_object?(property)
        fields(property, name, depth + 1)
      elsif types(property).include?("array") && inline_object?(property["items"] || {})
        fields(property["items"], "#{name}[]", depth + 1)
      else
        []
      end
    end

    def inline_object?(schema) = schema["$ref"].nil? && schema["properties"].present?

    def type_label(schema)
      return ref_name(schema) if schema["$ref"]

      base = (types(schema) - [ "null" ]).first || (schema["properties"] ? "object" : "any")
      case base
      when "array" then "array of #{type_label(schema['items'] || {})}"
      when "string" then schema["format"] == "date-time" ? "datetime" : "string"
      when "object" then schema["additionalProperties"].is_a?(Hash) ? "map of #{type_label(schema['additionalProperties'])}" : "object"
      else base
      end
    end

    def ref_name(schema)
      ref = schema["$ref"] || schema.dig("items", "$ref")
      ref&.split("/")&.last
    end

    def types(schema) = Array(schema["type"]).map(&:to_s)

    def nullable?(schema) = types(schema).include?("null")

    def notes(schema)
      notes = []
      notes << "one of: #{schema['enum'].join(', ')}" if schema["enum"]
      notes << "items one of: #{schema.dig('items', 'enum').join(', ')}" if schema.dig("items", "enum")
      notes << "min #{schema['minimum']}" if schema["minimum"]
      notes << "max #{schema['maximum']}" if schema["maximum"]
      notes
    end

    def curl(verb, path, media, body)
      line = +"curl"
      line << " -X #{verb.upcase}" unless verb == "get"
      line << %( -H "Authorization: Bearer $TOKEN")
      if media == "application/json" && body.any?
        sample = body.select { |field| field.required && !field.name.include?(".") && !field.name.include?("[]") }
                     .to_h { |field| [ field.name, sample_value(field) ] }
        line << %( -H "Content-Type: application/json" -d '#{JSON.generate(sample)}')
      elsif media
        line << %( -F "file=@...")
      end
      line << %( "#{server_url}#{path}")
    end

    def sample_value(field)
      type = field.type.to_s
      return [] if type.start_with?("array")
      return {} if type.start_with?("map") || type == "object" || field.ref

      { "integer" => 1, "boolean" => true, "datetime" => "2026-01-01T00:00:00Z" }.fetch(type, "...")
    end
  end
end
