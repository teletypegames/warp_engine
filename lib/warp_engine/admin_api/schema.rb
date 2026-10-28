module WarpEngine
  module AdminApi
    # Builders of the JSON schema hashes the Admin API documents its inputs and answers with.
    module Schema
      module_function

      # A string schema with an optional description and further keywords.
      def string(description = nil, **options) = typed("string", description, options)
      # An integer schema.
      def integer(description = nil, **options) = typed("integer", description, options)
      # A boolean schema.
      def boolean(description = nil, **options) = typed("boolean", description, options)
      # A <tt>date-time</tt> formatted string schema.
      def datetime(description = nil, **options) = typed("string", description, options.merge(format: "date-time"))
      # A positive integer identifier schema.
      def id(description = "Identifier") = integer(description, minimum: 1)

      # A string schema restricted to +values+.
      def enum(values, description = nil, **options)
        string(description, **options.merge(enum: values.map(&:to_s)))
      end

      # An array schema of +items+.
      def array(items, description = nil, **options)
        typed("array", description, options.merge(items: items))
      end

      # An object schema of +properties+.
      #
      # [required]    the required property names
      # [description] an optional description
      # [additional]  the +additionalProperties+ value (default +false+)
      def object(properties, required: [], description: nil, additional: false)
        {
          type:                 "object",
          description:          description,
          properties:           properties,
          required:             required.presence&.map(&:to_s),
          additionalProperties: additional
        }.compact
      end

      # +schema+ also allowing +null+; a schema without a type is returned as is.
      def nullable(schema)
        type = schema[:type]
        return schema if type.nil?

        types = Array(type)
        types.include?("null") ? schema : schema.merge(type: types + [ "null" ])
      end

      # A reference to the component schema +name+.
      def ref(name) = { "$ref": "#/components/schemas/#{name}" }

      # The type names of +schema+ as strings; empty for +nil+ or an untyped schema.
      def types(schema)
        Array(schema && schema[:type]).map(&:to_s)
      end

      # A schema of +type+ with +description+ and +options+, nil values dropped.
      def typed(type, description, options)
        { type: type, description: description }.merge(options).compact
      end
    end
  end
end
