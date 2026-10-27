module WarpEngine
  class Configuration
    # An OpenAPI object schema for one additional resource entry. The names are
    # the attributes' own; the schema carries them in camelCase, as
    # AdditionalResource#serialize does. `null: true` lets a property be null,
    # its enum included.
    class SchemaDSL
      TYPES = %w[string integer number boolean array object].freeze

      def self.build(&block)
        schema = new
        schema.instance_eval(&block)
        schema.to_h
      end

      def initialize
        @properties = {}
      end

      TYPES.each do |type|
        define_method(type) do |*names, null: false, enum: nil, **extra|
          raise ArgumentError, "#{type} needs a property name" if names.empty?

          names.each { |name| property(name, type, null: null, enum: enum, **extra) }
        end
      end

      def property(name, type, null: false, enum: nil, **extra)
        schema = { type: null ? [ type, "null" ] : type }
        schema[:enum] = null && !enum.include?(nil) ? [ nil, *enum ] : enum if enum
        @properties[name.to_s.camelize(:lower).to_sym] = schema.merge(extra)
      end

      def to_h = { type: "object", properties: @properties }
    end
  end
end
