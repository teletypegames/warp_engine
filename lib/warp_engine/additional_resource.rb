module WarpEngine
  class AdditionalResource
    attr_reader :subject, :association, :label, :permitted, :fields, :multiple, :api_schema, :api_serializer

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

    def attributes_key
      :"#{association}_attributes"
    end

    def permitted_params
      { attributes_key => permitted }
    end

    def render(form)
      fields.call(form)
    end

    def api?
      api_schema.present?
    end

    def api_attributes
      permitted.map(&:to_s) - [ "_destroy" ]
    end

    def serialize(record)
      return nil if record.nil?
      return api_serializer.call(record).as_json if api_serializer

      api_attributes.select { |name| record.respond_to?(name) }
                    .to_h { |name| [ name.camelize(:lower), record.public_send(name) ] }
                    .as_json
    end

    def value_for(owner)
      value = owner.public_send(association)
      multiple ? Array(value).map { |record| serialize(record) } : serialize(value)
    end

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
      def for(subject)
        Array(WarpEngine.config.additional_resources).select { |resource| resource.subject == subject.to_sym }
      end

      def api_for(subject)
        self.for(subject).select(&:api?)
      end

      def permitted_params_for(subject)
        self.for(subject).map(&:permitted_params)
      end
    end
  end
end
