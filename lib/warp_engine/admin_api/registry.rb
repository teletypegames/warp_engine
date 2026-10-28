module WarpEngine
  module AdminApi
    # The resources and operations of the Admin API, built once from the Definitions modules.
    module Registry
      module_function

      # The Definitions modules, in the order their resources are listed.
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

      # Every Resource, built on first use and memoized.
      def resources
        @resources ||= build
      end

      # Every Operation of every Resource.
      def operations
        resources.flat_map(&:operations)
      end

      # The Resource named +name+, or +nil+.
      def resource(name)
        resources.find { |resource| resource.name == name.to_sym }
      end

      # The Operation whose Operation#key is +key+ (<tt>"softwares.list"</tt>), or +nil+.
      def find(key)
        operations.find { |operation| operation.key == key.to_s }
      end

      # The Operation whose MCP tool name is +name+, or +nil+.
      def find_tool(name)
        operations.find { |operation| operation.tool_name == name.to_s }
      end

      # Forgets the built resources so the next call builds them again.
      def reset!
        @resources = nil
      end

      # Runs every definition against a new Builder and returns the resources it collected.
      def build
        builder = Builder.new
        definitions.each { |definition| definition.define(builder) }
        builder.resources
      end

      # Collects the resources a definition declares; passed as +api+ to <tt>define</tt>.
      class Builder
        # The resources declared so far.
        attr_reader :resources

        # Starts with no resources.
        def initialize
          @resources = []
        end

        # Declares a Resource named +name+ with +options+ (see Resource.new), yields it
        # for its operations and returns it.
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
