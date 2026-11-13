require "warp_engine/asset_kind"
require "warp_engine/platform/definition"

module WarpEngine
  # A platform a software is built for (TIC-80, Godot, C64, ...): the builtin
  # ones (<tt>lib/warp_engine/platform/builtin.rb</tt>) plus those a host
  # registers with WarpEngine::Configuration#register_platform. Everything the
  # engine knows of a platform is its Definition: the asset kinds a publish
  # accepts and the pipeline builds, the metadata source, the CI template.
  # Platforms compare equal by name, also to a String.
  class Platform
    # The form a registered platform name must have.
    FORMAT = /\A[a-z0-9_]{2,32}\z/

    # A platform registered the pre-1.12 way, with a service class built from
    # WarpEngine::Platforms::Updatable: its +name+, +service+ class name,
    # +built_kinds+, adapter-specific CI +templates+ (adapter name to path) and
    # +version_source+ command. Deprecated: register a platform with a block.
    Registration = Struct.new(:name, :service, :built_kinds, :templates, :version_source, keyword_init: true)

    class << self
      # Declares the builtin platform +name+ with the Builder DSL. Returns its
      # Definition.
      def define(name, &block)
        builder = Builder.new(name)
        builder.instance_eval(&block)
        builtin_definitions[name.to_s] = builder.build
      end

      # Returns the builtin Definitions, keyed by name.
      def builtin_definitions = (@builtin_definitions ||= {})

      # Returns the builtin names followed by the registered ones.
      def names = builtin_definitions.keys + (registrations.keys - builtin_definitions.keys)

      # Returns a Platform for every name.
      def all = names.map { |name| new(name) }

      # Returns +true+ when +name+ is a builtin or registered platform.
      def exists?(name) = names.include?(name.to_s)

      # Returns +true+ when +name+ is a builtin platform.
      def builtin?(name) = builtin_definitions.key?(name.to_s)

      # Returns the Platform named +name+, or +nil+ when there is none.
      def find(name)
        return nil unless exists?(name)

        new(name.to_s)
      end

      # Returns the Platform named +name+. Raises ArgumentError when there is none.
      def find!(name)
        find(name) || raise(ArgumentError, "Unsupported platform: #{name}")
      end

      # Returns what the host registered as +name+ (a Definition or a legacy
      # Registration), or +nil+.
      def registration(name) = registrations[name.to_s]

      # Returns every registration, keyed by name.
      def registrations = WarpEngine.config.platforms
    end

    # The platform name as a String.
    attr_reader :name

    # Creates the platform +name+ without checking that it exists.
    def initialize(name)
      @name = name.to_s
    end

    # Returns the Definition: the registered one, the one built from a legacy
    # Registration's service class, or the builtin one. Raises ArgumentError
    # for an unknown platform.
    def definition
      registered = self.class.registration(name)
      return registered if registered.is_a?(Definition)
      return legacy_service_class.definition if registered

      self.class.builtin_definitions.fetch(name) { raise ArgumentError, "Unsupported platform: #{name}" }
    end

    # Returns the human-readable platform name.
    def label = definition.label

    # Returns the KindSpec list.
    def kind_specs = definition.kind_specs

    # Returns the release asset kinds the platform publishes.
    def expected_kinds = definition.expected_kinds

    # Returns the expected kinds a release must have.
    def required_kinds = definition.required_kinds

    # Returns the expected kinds a release may lack.
    def optional_kinds = definition.optional_kinds

    # Returns the kinds the platform's pipeline builds; a legacy registration's
    # +built_kinds+ when it names them.
    def built_kinds
      legacy = legacy_registration&.built_kinds.presence
      legacy || definition.built_kinds
    end

    # Returns the CI release rule the platform forces (<tt>"tag"</tt>), or +nil+.
    def release_rule = definition.release_rule

    # Returns the shell command that prints the version of the source, or +nil+
    # for the default (the +version+ of <tt>metadata.json</tt>).
    def version_source = legacy_registration&.version_source.presence || definition.version_source

    # Returns the folder spec of asset +kind+ on a +folders+ shelf, read from the
    # release +metadata+, or +nil+ when the platform has none.
    def shelf_folder(metadata, kind) = definition.shelf_folder&.call(metadata, kind)

    # Returns +true+ for a platform registered the pre-1.12 way (a Registration).
    def legacy? = !legacy_registration.nil?

    # Returns the adapter-specific template a legacy registration names for the
    # CI +adapter+ (a Symbol), or +nil+.
    def legacy_template(adapter) = legacy_registration&.templates&.dig(adapter.to_sym)

    # Publishes the upload <tt>name-version</tt> of the file container: a legacy
    # platform through its service's +update+, every other one through
    # WarpEngine::Publish::Publisher. Returns the WarpEngine::Release; raises
    # WarpEngine::Platforms::MissingAssetsError when a required kind is missing.
    def publish(software_name, version)
      return legacy_service_class.new.update(software_name, version) if legacy_registration

      WarpEngine::Publish::Publisher.new(definition).publish(software_name, version)
    end

    # Returns the name.
    def to_s = name

    # Returns +true+ when +other+ is a Platform of the same name or a value whose
    # +to_s+ is the name. Also available as +eql?+.
    def ==(other)
      other.is_a?(Platform) ? name == other.name : name == other.to_s
    end
    alias eql? ==

    # Returns the hash of the name, so equal platforms hash alike.
    def hash = name.hash

    private

    def legacy_registration
      registered = self.class.registration(name)
      registered if registered.is_a?(Registration)
    end

    def legacy_service_class = legacy_registration.service.to_s.constantize
  end
end

require "warp_engine/platform/builtin"
