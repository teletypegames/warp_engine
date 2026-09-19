module WarpEngine
  class AdditionalResource
    attr_reader :subject, :association, :label, :permitted, :fields, :multiple

    def initialize(subject:, association:, label:, permitted:, fields:, multiple: true)
      @subject     = subject.to_sym
      @association = association.to_sym
      @label       = label
      @permitted   = Array(permitted)
      @fields      = fields
      @multiple    = multiple

      raise ArgumentError, "fields must be callable" unless fields.respond_to?(:call)
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

    class << self
      def for(subject)
        Array(WarpEngine.config.additional_resources).select { |resource| resource.subject == subject.to_sym }
      end

      def permitted_params_for(subject)
        self.for(subject).map(&:permitted_params)
      end
    end
  end
end
