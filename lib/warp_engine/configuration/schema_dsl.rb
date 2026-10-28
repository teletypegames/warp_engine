module WarpEngine
  class Configuration
    # An OpenAPI object schema for one additional resource entry. The names are
    # the attributes' own; the schema carries them in camelCase, as
    # AdditionalResource#serialize does. <tt>null: true</tt> lets a property be null,
    # its enum included.
    #
    #   api_schema do
    #     string :locale, :title
    #     string :og_type, null: true, enum: %w[website article]
    #   end
    #
    # Each JSON type in TYPES is a method taking one or more property names and
    # the +null+, +enum+ and extra schema options; it raises ArgumentError
    # without a name.
    class SchemaDSL
      # The JSON schema types that get a DSL method.
      TYPES = %w[string integer number boolean array object].freeze

      # Evaluates +block+ in a new SchemaDSL and returns the schema Hash.
      def self.build(&block)
        schema = new
        schema.instance_eval(&block)
        schema.to_h
      end

      # Creates an empty object schema.
      def initialize
        @properties = {}
      end

      TYPES.each do |type|
        define_method(type) do |*names, null: false, enum: nil, **extra|
          raise ArgumentError, "#{type} needs a property name" if names.empty?

          names.each { |name| property(name, type, null: null, enum: enum, **extra) }
        end
      end

      # Adds the property +name+ (camelCased) of JSON +type+. With +null+ the type
      # also allows null and +nil+ joins the +enum+; +extra+ is merged into the
      # property schema.
      def property(name, type, null: false, enum: nil, **extra)
        schema = { type: null ? [ type, "null" ] : type }
        schema[:enum] = null && !enum.include?(nil) ? [ nil, *enum ] : enum if enum
        @properties[name.to_s.camelize(:lower).to_sym] = schema.merge(extra)
      end

      # Returns the schema as <tt>{ type: "object", properties: {...} }</tt>.
      def to_h = { type: "object", properties: @properties }
    end
  end
end
