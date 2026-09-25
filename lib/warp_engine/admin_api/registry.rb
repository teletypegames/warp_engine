module WarpEngine
  module AdminApi
    module Registry
      module_function

      def definitions
        [
          Definitions::Meta,
          Definitions::Catalog,
          Definitions::Vocabulary,
          Definitions::Statistics,
          Definitions::Pipelines,
          Definitions::Files,
          Definitions::Tokens
        ]
      end

      def resources
        @resources ||= build
      end

      def operations
        resources.flat_map(&:operations)
      end

      def resource(name)
        resources.find { |resource| resource.name == name.to_sym }
      end

      def find(key)
        operations.find { |operation| operation.key == key.to_s }
      end

      def find_tool(name)
        operations.find { |operation| operation.tool_name == name.to_s }
      end

      def reset!
        @resources = nil
      end

      def build
        builder = Builder.new
        definitions.each { |definition| definition.define(builder) }
        builder.resources
      end

      class Builder
        attr_reader :resources

        def initialize
          @resources = []
        end

        def resource(name, **options)
          resource = Resource.new(name, **options)
          yield resource
          @resources << resource
          resource
        end
      end
    end
  end
end
