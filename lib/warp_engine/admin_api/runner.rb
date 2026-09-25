module WarpEngine
  module AdminApi
    class Runner
      TRUE_VALUES  = %w[true 1 yes on].freeze
      FALSE_VALUES = %w[false 0 no off].freeze

      def self.call(operation, principal:, params:, base_url: nil, via: :http)
        new(operation, principal: principal, params: params, base_url: base_url, via: via).call
      end

      def initialize(operation, principal:, params:, base_url:, via:)
        @operation = operation
        @principal = principal
        @raw       = params.to_h.deep_stringify_keys
        @base_url  = base_url
        @via       = via
      end

      def call
        gate!
        context = Context.new(operation: @operation, principal: @principal, params: coerced_params,
                              base_url: @base_url, via: @via)
        result = @operation.handler.call(context)
        instrument(result) unless @operation.read?
        result
      rescue Error
        raise
      rescue ActiveRecord::RecordNotFound, Errno::ENOENT
        raise Error.not_found
      rescue ActiveRecord::RecordInvalid => e
        raise Error.invalid(e.record)
      rescue ActiveRecord::InvalidForeignKey
        raise Error.new(422, "Validation failed", details: { base: [ "refers to a record that does not exist" ] })
      rescue ActiveRecord::RecordNotUnique, Errno::EEXIST
        raise Error.conflict("Already exists")
      rescue Errno::ENOTEMPTY
        raise Error.conflict("Directory not empty")
      rescue WarpEngine::CI::Error => e
        raise Error.new(502, "CI: #{e.message}")
      rescue ArgumentError => e
        raise Error.bad_request(e.message)
      end

      def self.gate(operation, principal)
        config = AdminApi.config
        resource = operation.resource

        raise Error.not_found unless config.enabled?
        raise Error.not_found unless resource.always? || config.resource_enabled?(resource.name)
        raise Error.unauthorized if principal.nil?
        raise Error.new(resource.unavailable[:status], resource.unavailable[:message]) unless resource.available?
        raise Error.read_only if config.read_only? && !operation.read?

        scope = operation.required_scope
        raise Error.forbidden("This needs the #{scope} scope") unless scope == :any || principal.scope?(scope)
      end

      def self.permitted?(operation, principal)
        gate(operation, principal)
        true
      rescue Error
        false
      end

      private

      def gate!
        self.class.gate(@operation, @principal)
      end

      def coerced_params
        @operation.inputs.each_with_object({}) do |(key, schema), params|
          next unless @raw.key?(key)

          params[key] = coerce(key, @raw[key], schema)
        end.tap do |params|
          params["file"] = @raw["file"] if @operation.multipart? && @raw.key?("file")
        end
      end

      def coerce(key, value, schema)
        return value unless value.is_a?(String)

        types = Schema.types(schema)
        return nil if value.empty? && types.include?("null")

        if types.include?("integer")
          Integer(value, 10)
        elsif types.include?("boolean")
          boolean(key, value)
        else
          value
        end
      rescue ArgumentError
        raise Error.bad_request("#{key} must be an integer")
      end

      def boolean(key, value)
        return true if TRUE_VALUES.include?(value.downcase)
        return false if FALSE_VALUES.include?(value.downcase)

        raise Error.bad_request("#{key} must be true or false")
      end

      def instrument(result)
        ActiveSupport::Notifications.instrument(
          "warp_engine.admin_api.write",
          principal: @principal,
          operation: @operation.key,
          resource:  @operation.resource.name,
          action:    @operation.name,
          via:       @via,
          data:      result&.data
        )
      end
    end
  end
end
