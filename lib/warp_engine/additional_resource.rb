module WarpEngine
  # A host-owned association shown on an engine admin page and, optionally,
  # in the admin API: the host's own fields next to an engine record (SEO
  # metadata, notes, translations) without the engine knowing what they are.
  # Built by WarpEngine::Configuration::DSL#additional_resource and kept in
  # WarpEngine.config.additional_resources.
  class AdditionalResource
    # [subject]        the engine resource the association hangs on, e.g. +:software+
    # [association]    the association name on that resource
    # [label]          the fieldset title on the admin form
    # [permitted]      the attributes the admin form permits
    # [fields]         the callable that renders the form fields
    # [multiple]       +true+ for a +has_many+, +false+ for a +has_one+
    # [api_schema]     the OpenAPI schema of one entry, or +nil+ to keep it out of the API
    # [api_serializer] the callable that turns one record into its API Hash, or +nil+
    attr_reader :subject, :association, :label, :permitted, :fields, :multiple, :api_schema, :api_serializer

    # Creates the resource from the attributes of the same names. Raises
    # ArgumentError when +fields+, or a given +api_serializer+, is not callable.
    def initialize(subject:, association:, label:, permitted:, fields:, multiple: true,
                   api_schema: nil, api_serializer: nil)
      @subject        = subject.to_sym
      @association    = association.to_sym
      @label          = label
      @permitted      = Array(permitted)
      @fields         = fields
      @multiple       = multiple
      @api_schema     = api_schema
      @api_serializer = api_serializer

      raise ArgumentError, "fields must be callable" unless fields.respond_to?(:call)
      raise ArgumentError, "api_serializer must be callable" if api_serializer && !api_serializer.respond_to?(:call)
    end

    # Returns the nested attributes key, e.g. +:seo_metadata_attributes+.
    def attributes_key
      :"#{association}_attributes"
    end

    # Returns the strong parameters entry: <tt>{ attributes_key => permitted }</tt>.
    def permitted_params
      { attributes_key => permitted }
    end

    # Renders the form fields by calling #fields with the ActiveAdmin +form+.
    def render(form)
      fields.call(form)
    end

    # Returns +true+ when the resource has an API schema and so appears in the API.
    def api?
      api_schema.present?
    end

    # Returns the permitted attribute names as strings, without +_destroy+.
    def api_attributes
      permitted.map(&:to_s) - [ "_destroy" ]
    end

    # Returns the JSON-ready Hash of +record+: the #api_serializer result, or
    # else its #api_attributes under camelCase keys. Returns +nil+ for +nil+.
    def serialize(record)
      return nil if record.nil?
      return api_serializer.call(record).as_json if api_serializer

      api_attributes.select { |name| record.respond_to?(name) }
                    .to_h { |name| [ name.camelize(:lower), record.public_send(name) ] }
                    .as_json
    end

    # Returns the serialized association of the engine record +owner+: an Array
    # of Hashes when #multiple, else one Hash or +nil+.
    def value_for(owner)
      value = owner.public_send(association)
      multiple ? Array(value).map { |record| serialize(record) } : serialize(value)
    end

    # Turns an API +value+ (camelCase keys) into nested attributes: keys
    # underscored and sliced to #permitted. Expects an Array of Hashes when
    # #multiple, else one Hash; raises ArgumentError otherwise.
    def nested_attributes(value)
      permitted_keys = permitted.map(&:to_s)
      clean = lambda do |item|
        raise ArgumentError, "#{association} expects an object per entry" unless item.is_a?(Hash)

        item.to_h.transform_keys { |key| key.to_s.underscore }.slice(*permitted_keys)
      end

      if multiple
        raise ArgumentError, "#{association} expects an array" unless value.is_a?(Array)

        value.map(&clean)
      else
        clean.call(value)
      end
    end

    class << self
      # Returns the configured resources hanging on +subject+.
      def for(subject)
        Array(WarpEngine.config.additional_resources).select { |resource| resource.subject == subject.to_sym }
      end

      # Returns the resources on +subject+ that appear in the API.
      def api_for(subject)
        self.for(subject).select(&:api?)
      end

      # Returns the strong parameters entries of every resource on +subject+.
      def permitted_params_for(subject)
        self.for(subject).map(&:permitted_params)
      end
    end
  end
end
