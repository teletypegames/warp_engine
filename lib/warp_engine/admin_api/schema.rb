module WarpEngine
  module AdminApi
    module Schema
      module_function

      def string(description = nil, **options) = typed("string", description, options)
      def integer(description = nil, **options) = typed("integer", description, options)
      def boolean(description = nil, **options) = typed("boolean", description, options)
      def datetime(description = nil, **options) = typed("string", description, options.merge(format: "date-time"))
      def id(description = "Identifier") = integer(description, minimum: 1)

      def enum(values, description = nil, **options)
        string(description, **options.merge(enum: values.map(&:to_s)))
      end

      def array(items, description = nil, **options)
        typed("array", description, options.merge(items: items))
      end

      def object(properties, required: [], description: nil, additional: false)
        {
          type:                 "object",
          description:          description,
          properties:           properties,
          required:             required.presence&.map(&:to_s),
          additionalProperties: additional
        }.compact
      end

      def nullable(schema)
        type = schema[:type]
        return schema if type.nil?

        types = Array(type)
        types.include?("null") ? schema : schema.merge(type: types + [ "null" ])
      end

      def ref(name) = { "$ref": "#/components/schemas/#{name}" }

      def types(schema)
        Array(schema && schema[:type]).map(&:to_s)
      end

      def typed(type, description, options)
        { type: type, description: description }.merge(options).compact
      end
    end
  end
end
