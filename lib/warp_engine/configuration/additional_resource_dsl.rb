module WarpEngine
  class Configuration
    # The block of an +additional_resource+ line in WarpEngine::Configuration::DSL;
    # it collects the parts of one WarpEngine::AdditionalResource.
    class AdditionalResourceDSL
      # Creates a builder for +association+ on the engine resource +subject+,
      # shown under +label+; +multiple+ is +false+ for a +has_one+.
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

      # Adds attributes to the strong parameters of the admin form.
      def permit(*attributes) = @permitted.concat(attributes.flatten)

      # Sets the ActiveAdmin form block rendered in the resource's fieldset.
      def form(&block) = @fields = block

      # Sets the OpenAPI schema of one entry: a Hash, or a block evaluated by
      # WarpEngine::Configuration::SchemaDSL.
      def api_schema(schema = nil, &block)
        @api_schema = schema || SchemaDSL.build(&block)
      end

      # Sets the callable (or the block) that turns one entry into its API Hash.
      def api_serializer(callable = nil, &block)
        @api_serializer = callable || block
      end

      # Returns the WarpEngine::AdditionalResource built from the collected parts.
      def build
        AdditionalResource.new(subject: @subject, association: @association, label: @label, multiple: @multiple,
                               permitted: @permitted, fields: @fields,
                               api_schema: @api_schema, api_serializer: @api_serializer)
      end
    end
  end
end
