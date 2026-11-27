require "warp_engine/runtime/controls"
require "warp_engine/runtime/definition"
require "warp_engine/runtime/template"

module WarpEngine
  # A runtime environment a release plays in on the web: EmulatorJS, the
  # TIC-80 player, ... A runtime knows nothing of platforms; a platform binds
  # to a runtime (WarpEngine::Platform::WebBinding) with the parameters it
  # needs, so one runtime serves many platforms and a platform may offer more
  # than one runtime.
  #
  # Everything the engine knows of a runtime is its Definition: where its
  # files come from (downloaded from a pinned source with a SHA-256 per file,
  # or uploaded by a build), its components (e.g. the cores of EmulatorJS),
  # its parameters and its page template. The builtin runtimes are in
  # <tt>lib/warp_engine/runtime/builtin.rb</tt>; a host adds its own with
  # WarpEngine::Configuration#register_runtime. The installed copies are
  # WarpEngine::RuntimeVersion records, their files under
  # <tt>_runtimes/<name>-<version>/</tt> of the file container.
  # Runtimes compare equal by name, also to a String.
  class Runtime
    # The form a runtime name must have.
    FORMAT = /\A[a-z0-9_]{2,32}\z/

    # The directory of the file container the installed runtimes live under.
    ROOT = "_runtimes".freeze

    # The name the licence notice of a runtime has in its installed folder.
    NOTICE = "LICENSES.txt".freeze

    class << self
      # Declares the builtin runtime +name+ with the Builder DSL. Returns its
      # Definition.
      def define(name, &block)
        builder = Builder.new(name)
        builder.instance_eval(&block)
        builtin_definitions[name.to_s] = builder.build
      end

      # Returns the builtin Definitions, keyed by name.
      def builtin_definitions = (@builtin_definitions ||= {})

      # Returns the builtin names followed by the registered ones.
      def names = builtin_definitions.keys + (WarpEngine.config.runtimes.keys - builtin_definitions.keys)

      # Returns a Runtime for every name.
      def all = names.map { |name| new(name) }

      # Returns +true+ when +name+ is a builtin or registered runtime.
      def exists?(name) = names.include?(name.to_s)

      # Returns +true+ when +name+ is a builtin runtime.
      def builtin?(name) = builtin_definitions.key?(name.to_s)

      # Returns the Runtime named +name+, or +nil+ when there is none.
      def find(name)
        return nil unless exists?(name)

        new(name.to_s)
      end

      # Returns the Runtime named +name+. Raises ArgumentError when there is none.
      def find!(name)
        find(name) || raise(ArgumentError, "Unknown runtime: #{name}")
      end

      # Returns the directory of the version +version+ of the runtime +name+,
      # relative to the file container.
      def directory(name, version) = "#{ROOT}/#{name}-#{version}"
    end

    # The runtime name as a String.
    attr_reader :name

    # Creates the runtime +name+ without checking that it exists.
    def initialize(name)
      @name = name.to_s
    end

    # Returns the Definition: the one the host registered, or the builtin one.
    # Raises ArgumentError for an unknown runtime.
    def definition
      WarpEngine.config.runtimes[name] ||
        self.class.builtin_definitions.fetch(name) { raise ArgumentError, "Unknown runtime: #{name}" }
    end

    # Returns the human-readable name.
    def label = definition.label

    # Returns +true+ when the files are downloaded from a pinned source.
    def download? = definition.download?

    # Returns +true+ when a build uploads the files.
    def upload? = definition.upload?

    # Returns the version the host chose (WarpEngine::Configuration#runtime),
    # else the newest declared one, else +nil+ (an uploaded runtime then uses
    # its newest installed version).
    def chosen_version
      WarpEngine.config.runtime_versions[name].presence || definition.versions.keys.last
    end

    # Returns the installed WarpEngine::RuntimeVersion the new releases bind
    # to: the chosen version, or for an uploaded runtime without a choice the
    # newest installed one. +nil+ when it is not installed.
    def current_version
      scope = WarpEngine::RuntimeVersion.kept.where(name: name)
      version = chosen_version
      version ? scope.find_by(version: version) : scope.order(created_at: :desc, id: :desc).first
    end

    # Returns the platform web bindings that use this runtime, as
    # [WarpEngine::Platform, WarpEngine::Platform::WebBinding] pairs (enabled
    # ones only, unless +all+).
    def bindings(all: false)
      WarpEngine::Platform.all.flat_map do |platform|
        list = all ? platform.all_web_bindings : platform.web_bindings
        list.select { |binding| binding.runtime == name }.map { |binding| [ platform, binding ] }
      end
    end

    # Returns the names of the platforms bound to this runtime.
    def platforms = bindings.map { |platform, _| platform.name }.uniq

    # Returns the component keys the enabled bindings need, as a Hash of
    # component kind to keys, e.g. <tt>{ "core" => ["vice_x64sc"] }</tt>.
    def required_components
      definition.params.each_value.with_object(Hash.new { |hash, key| hash[key] = [] }) do |param, needed|
        next unless param.component

        bindings.each do |_, binding|
          key = binding.params[param.name.to_sym]
          needed[param.component.to_s] |= [ key.to_s ] if key.present?
        end
      end.to_h
    end

    # Returns the name.
    def to_s = name

    # Returns +true+ when +other+ is a Runtime of the same name or a value
    # whose +to_s+ is the name. Also available as +eql?+.
    def ==(other)
      other.is_a?(Runtime) ? name == other.name : name == other.to_s
    end
    alias eql? ==

    # Returns the hash of the name, so equal runtimes hash alike.
    def hash = name.hash
  end
end

require "warp_engine/runtime/builtin"
