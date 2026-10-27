module WarpEngine
  class Configuration
    class AdditionalResourceDSL
      def initialize(association, subject:, label:, multiple:)
        @association    = association
        @subject        = subject
        @label          = label
        @multiple       = multiple
        @permitted      = []
        @fields         = nil
        @api_schema     = nil
        @api_serializer = nil
      end

      def permit(*attributes) = @permitted.concat(attributes.flatten)

      def form(&block) = @fields = block

      def api_schema(schema = nil, &block)
        @api_schema = schema || SchemaDSL.build(&block)
      end

      def api_serializer(callable = nil, &block)
        @api_serializer = callable || block
      end

      def build
        AdditionalResource.new(subject: @subject, association: @association, label: @label, multiple: @multiple,
                               permitted: @permitted, fields: @fields,
                               api_schema: @api_schema, api_serializer: @api_serializer)
      end
    end
  end
end
