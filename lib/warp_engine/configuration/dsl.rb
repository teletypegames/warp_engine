require "warp_engine/configuration/admin_api_dsl"
require "warp_engine/configuration/schema_dsl"
require "warp_engine/configuration/additional_resource_dsl"
require "warp_engine/configuration/ci_dsl"

module WarpEngine
  class Configuration
    # The block form of WarpEngine.configure: <tt>WarpEngine.configure do ... end</tt>
    # without a block parameter runs here. Every call writes the same settings
    # the <tt>c.setting = value</tt> form does, so the rest of the engine reads one
    # Configuration either way. The collections (shelves, extras, platforms,
    # ignored user agents) are keyed, so a block that runs again on a reload
    # replaces its entries instead of adding them twice.
    class DSL
      # The settings that map one to one onto a WarpEngine::Configuration
      # writer; each gets a DSL method of the same name taking the value.
      SETTINGS = %i[site_url file_container_path update_secret max_upload_size enforce_software_ownership
                    image_adapter access_policy access_token_owner_class identity_verification_url
                    device_code_ttl device_code_interval catalog_page_size catalog_max_page_size].freeze

      # Evaluates +block+ against a new DSL writing into +config+ and returns
      # +config+.
      def self.apply(config, &block)
        new(config).instance_eval(&block)
        config
      end

      # Creates a DSL writing into the WarpEngine::Configuration +config+.
      def initialize(config)
        @config = config
      end

      SETTINGS.each do |name|
        define_method(name) { |value| @config.public_send(:"#{name}=", value) }
      end

      # Sets the <tt>/build/*</tt> authentication source.
      #
      # [from]  +:env+ (the shared update secret) or +:database+ (application tokens)
      # [owner] class name of the owner database tokens belong to
      def application_tokens(from:, owner: nil)
        @config.application_token_source      = from
        @config.application_token_owner_class = owner&.to_s
      end

      # Sets the class name of the host's image model.
      def image_class(name) = @config.image_class_name = name.to_s

      # Sets the storage adapter: +:local+ or an adapter object (see WarpEngine::Storage).
      def storage(adapter) = @config.storage_adapter = adapter

      # Sets the callable (or the block) that takes a request and returns the
      # subject of its session, for callers without a bearer token.
      def subject_resolver(callable = nil, &block)
        @config.subject_resolver = callable || block
      end

      # Adds user agent patterns the download statistics leave out; strings may
      # use <tt>*</tt> as a wildcard. Duplicates are dropped.
      def ignore_user_agents(*patterns)
        @config.ignored_user_agents = (Array(@config.ignored_user_agents) + patterns.flatten).uniq
      end

      # Defines a shelf for +platform+ (see WarpEngine::Shelves for the options).
      # A shelf with the same +path+ is replaced. Raises ArgumentError on an
      # unknown option key.
      def shelf(platform, **options)
        unknown = options.keys - (Shelves::KEYS - [ :platform ])
        raise ArgumentError, "unknown shelf keys for #{platform}: #{unknown.join(', ')}" if unknown.any?

        definition = { platform: platform.to_s, **options }
        @config.shelves = Array(@config.shelves).reject { |other| other.to_h.symbolize_keys[:path] == definition[:path] } + [ definition ]
      end

      # Registers a platform; see WarpEngine::Configuration#register_platform.
      def register_platform(name, **options) = @config.register_platform(name, **options)

      # Evaluates +block+ with a WarpEngine::Configuration::AdminApiDSL on the
      # admin API settings.
      def admin_api(&block)
        AdminApiDSL.new(@config.admin_api).instance_eval(&block)
      end

      # Adds host fields to an engine admin page.
      #
      # [association] the host association on the engine model
      # [on]          the engine resource it hangs on, e.g. +:software+
      # [label]       the fieldset title
      # [multiple]    +false+ for a +has_one+ association
      #
      # The block runs with a WarpEngine::Configuration::AdditionalResourceDSL.
      # An entry with the same subject and association is replaced.
      def additional_resource(association, on:, label:, multiple: true, &block)
        builder = AdditionalResourceDSL.new(association, subject: on, label: label, multiple: multiple)
        builder.instance_eval(&block) if block
        resource = builder.build

        @config.additional_resources = Array(@config.additional_resources).reject do |other|
          other.subject == resource.subject && other.association == resource.association
        end + [ resource ]
      end

      # Sets the CI adapter: <tt>ci :none</tt>, <tt>ci :woodpecker</tt> (from ENV),
      # <tt>ci SomeAdapter.new</tt>, or <tt>ci :woodpecker do ... end</tt> to name the
      # server and its platforms here (see WarpEngine::Configuration::CIDSL).
      def ci(adapter, &block)
        @config.ci_adapter = block ? CIDSL.build(adapter, &block) : adapter
      end
    end
  end
end
