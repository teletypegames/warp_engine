require "warp_engine/asset_kind"
require "warp_engine/platform/web_binding"
require "warp_engine/platform/definition"

module WarpEngine
  # A platform a software is built for (TIC-80, Godot, C64, ...): the builtin
  # ones (<tt>lib/warp_engine/platform/builtin.rb</tt>) plus those a host
  # registers with WarpEngine::Configuration#register_platform. Everything the
  # engine knows of a platform is its Definition: the asset kinds a publish
  # accepts and the pipeline builds, the metadata source, the CI template.
  # Platforms compare equal by name, also to a String. A platform with
  # variants (Builder#variant) is looked up for one +app+; without one it is
  # its default variant.
  class Platform
    # The form a registered platform name must have.
    FORMAT = /\A[a-z0-9_]{2,32}\z/

    # The WebBinding attributes a host's +platform_web+ change may set; every
    # other option is a runtime parameter.
    WEB_BINDING_OPTIONS = %i[payload default enabled isolated].freeze

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

      # Returns the Platform named +name+ for the variant +app+ (blank: the
      # default one), or +nil+ when there is no such platform or variant.
      def find(name, app: nil)
        return nil unless exists?(name)

        platform = new(name.to_s, app: app)
        platform.definition
        platform
      rescue ArgumentError
        nil
      end

      # Returns the Platform named +name+ for the variant +app+. Raises
      # ArgumentError when there is no such platform or variant.
      def find!(name, app: nil)
        find(name, app: app) || raise(ArgumentError, app.present? ? "Unsupported platform: #{name} (app #{app})" : "Unsupported platform: #{name}")
      end

      # Returns the Platform of +software+ (a WarpEngine::Software, or anything
      # with +platform+ and +app+) for its variant, or +nil+.
      def for(software)
        return nil if software.nil?

        find(software.platform, app: software.try(:app))
      end

      # Returns what the host registered as +name+ (a Definition or a legacy
      # Registration), or +nil+.
      def registration(name) = registrations[name.to_s]

      # Returns every registration, keyed by name.
      def registrations = WarpEngine.config.platforms

      # Returns the WebBinding list +bindings+ with exactly one default among
      # the enabled ones: the last enabled one marked default, else the first
      # enabled one. A disabled binding is never the default.
      def with_default(bindings)
        enabled = bindings.select(&:enabled)
        chosen = enabled.reverse.find(&:default) || enabled.first
        bindings.map { |binding| binding.with(default: binding.equal?(chosen)) }
      end
    end

    # The platform name as a String.
    attr_reader :name

    # Creates the platform +name+ for the variant +app+ (blank: the default
    # one) without checking that they exist.
    def initialize(name, app: nil)
      @name = name.to_s
      @app = app.to_s.presence
    end

    # Returns the Definition: the registered one, the one built from a legacy
    # Registration's service class, or the builtin one. Raises ArgumentError
    # for an unknown platform.
    #
    # A platform with variants returns the Definition of the variant +app+
    # (Definition#variant); ArgumentError for a variant it does not have.
    def definition
      @definition ||= base_definition.variant(@app)
    end

    # Returns the variant this platform is (+cli+, +gui+), or +nil+ for a
    # platform without variants.
    def app = definition.app

    # Returns the variant names, the default first; empty without variants.
    def apps = definition.apps

    # Returns the platform for the variant +name+.
    def for_app(name) = self.class.find!(self.name, app: name)

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

    # Returns the Platform::MarkerOption list: the CI marker keys the
    # platform declares besides +platform+, +name+, +release+ and +app+.
    def options = definition.options

    # Returns the CI release rule the platform forces (<tt>"tag"</tt>), or +nil+.
    def release_rule = definition.release_rule

    # Returns the shell command that prints the version of the source, or +nil+
    # for the default (the +version+ of <tt>metadata.json</tt>).
    def version_source = legacy_registration&.version_source.presence || definition.version_source

    # Returns the JSON file the version source reads (Definition#version_file),
    # or +nil+.
    def version_file = legacy_registration&.version_source.presence ? nil : definition.version_file

    # Returns the folder spec of asset +kind+ on a +folders+ shelf, read from the
    # release +metadata+, or +nil+ when the platform has none.
    def shelf_folder(metadata, kind) = definition.shelf_folder&.call(metadata, kind)

    # Returns every WebBinding of the platform, the disabled ones too: the
    # definition's bindings with the host's WarpEngine::Configuration#platform_web
    # changes applied (a change to an existing key merges into it, any other
    # adds a binding). A legacy platform has none.
    def all_web_bindings
      bindings = legacy? ? [] : definition.web_bindings.dup
      chosen = nil
      WarpEngine.config.platform_web_changes.fetch(name, []).each do |change|
        key = (change[:as] || change[:runtime]).to_s
        index = bindings.index { |binding| binding.key == key }
        if index
          options = change.except(:runtime, :as)
          attributes = options.slice(*WEB_BINDING_OPTIONS).transform_values { |value| value.is_a?(Symbol) ? value.to_s : value }
          params = bindings[index].params.merge(options.except(*WEB_BINDING_OPTIONS)).freeze
          bindings[index] = bindings[index].with(**attributes, params: params)
        else
          bindings << WebBinding.build(change[:runtime], **change.except(:runtime))
        end
        chosen = key if change[:default]
      end
      bindings = bindings.map { |binding| binding.with(default: binding.key == chosen) } if chosen
      self.class.with_default(bindings)
    end

    # Returns the enabled WebBinding list; the default one is among them
    # unless the list is empty.
    def web_bindings = all_web_bindings.select(&:enabled)

    # Returns the enabled WebBinding with the key +key+, or the default one
    # when +key+ is blank; +nil+ when there is none.
    def web_binding(key = nil)
      key.blank? ? web_bindings.find(&:default) : web_bindings.find { |binding| binding.key == key.to_s }
    end

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

    def base_definition
      registered = self.class.registration(name)
      return registered if registered.is_a?(Definition)
      return legacy_service_class.definition if registered

      self.class.builtin_definitions.fetch(name) { raise ArgumentError, "Unsupported platform: #{name}" }
    end

    def legacy_registration
      registered = self.class.registration(name)
      registered if registered.is_a?(Registration)
    end

    def legacy_service_class = legacy_registration.service.to_s.constantize
  end
end

require "warp_engine/platform/builtin"
