require "warp_engine/configuration/admin_api_dsl"
require "warp_engine/configuration/schema_dsl"
require "warp_engine/configuration/additional_resource_dsl"
require "warp_engine/configuration/ci_dsl"

module WarpEngine
  class Configuration
    # The block form of WarpEngine.configure: `WarpEngine.configure do ... end`
    # without a block parameter runs here. Every call writes the same settings
    # the `c.setting = value` form does, so the rest of the engine reads one
    # Configuration either way. The collections (shelves, extras, platforms,
    # ignored user agents) are keyed, so a block that runs again on a reload
    # replaces its entries instead of adding them twice.
    class DSL
      SETTINGS = %i[site_url file_container_path update_secret max_upload_size enforce_software_ownership
                    image_adapter access_policy access_token_owner_class identity_verification_url
                    device_code_ttl device_code_interval catalog_page_size catalog_max_page_size].freeze

      def self.apply(config, &block)
        new(config).instance_eval(&block)
        config
      end

      def initialize(config)
        @config = config
      end

      SETTINGS.each do |name|
        define_method(name) { |value| @config.public_send(:"#{name}=", value) }
      end

      def application_tokens(from:, owner: nil)
        @config.application_token_source      = from
        @config.application_token_owner_class = owner&.to_s
      end

      def image_class(name) = @config.image_class_name = name.to_s

      def storage(adapter) = @config.storage_adapter = adapter

      def subject_resolver(callable = nil, &block)
        @config.subject_resolver = callable || block
      end

      def ignore_user_agents(*patterns)
        @config.ignored_user_agents = (Array(@config.ignored_user_agents) + patterns.flatten).uniq
      end

      def shelf(platform, **options)
        unknown = options.keys - (Shelves::KEYS - [ :platform ])
        raise ArgumentError, "unknown shelf keys for #{platform}: #{unknown.join(', ')}" if unknown.any?

        definition = { platform: platform.to_s, **options }
        @config.shelves = Array(@config.shelves).reject { |other| other.to_h.symbolize_keys[:path] == definition[:path] } + [ definition ]
      end

      def register_platform(name, **options) = @config.register_platform(name, **options)

      def admin_api(&block)
        AdminApiDSL.new(@config.admin_api).instance_eval(&block)
      end

      def additional_resource(association, on:, label:, multiple: true, &block)
        builder = AdditionalResourceDSL.new(association, subject: on, label: label, multiple: multiple)
        builder.instance_eval(&block) if block
        resource = builder.build

        @config.additional_resources = Array(@config.additional_resources).reject do |other|
          other.subject == resource.subject && other.association == resource.association
        end + [ resource ]
      end

      # `ci :none`, `ci :woodpecker` (from ENV), `ci SomeAdapter.new`, or
      # `ci :woodpecker do ... end` to name the server and its platforms here.
      def ci(adapter, &block)
        @config.ci_adapter = block ? CIDSL.build(adapter, &block) : adapter
      end
    end
  end
end
