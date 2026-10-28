module WarpEngine
  # A platform a software is built for (TIC-80, Godot, C64, ...): the builtin
  # ones plus those registered with WarpEngine::Configuration#register_platform.
  # Each delegates its details to a service class,
  # <tt>WarpEngine::Platforms::<Name>::Service</tt> unless the registration names
  # another. Platforms compare equal by name, also to a String.
  class Platform
    # The names of the platforms the engine ships.
    BUILTIN = %w[tic80 ebitengine love c64 plus4 godot bevy phaser dos].freeze
    # The builtin platform names; see Platform.names for the full list.
    NAMES = BUILTIN

    # The form a registered platform name must have.
    FORMAT = /\A[a-z0-9_]{2,32}\z/

    # A registered platform: its +name+, +service+ class name, +built_kinds+,
    # CI +templates+ (adapter name to path) and +version_source+ command.
    Registration = Struct.new(:name, :service, :built_kinds, :templates, :version_source, keyword_init: true)

    class << self
      # Returns the builtin names followed by the registered ones.
      def names = BUILTIN + (registrations.keys - BUILTIN)

      # Returns a Platform for every name.
      def all = names.map { |name| new(name) }

      # Returns +true+ when +name+ is a builtin or registered platform.
      def exists?(name) = names.include?(name.to_s)

      # Returns +true+ when +name+ is a builtin platform.
      def builtin?(name) = BUILTIN.include?(name.to_s)

      # Returns the Platform named +name+, or +nil+ when there is none.
      def find(name)
        return nil unless exists?(name)

        new(name.to_s)
      end

      # Returns the Platform named +name+. Raises ArgumentError when there is none.
      def find!(name)
        find(name) || raise(ArgumentError, "Unsupported platform: #{name}")
      end

      # Returns the Registration of +name+, or +nil+.
      def registration(name) = registrations[name.to_s]

      # Returns every Registration, keyed by name.
      def registrations = WarpEngine.config.platforms
    end

    # The platform name as a String.
    attr_reader :name

    # Creates the platform +name+ without checking that it exists.
    def initialize(name)
      @name = name.to_s
    end

    # Returns the platform's service class: the registered one, or else
    # <tt>WarpEngine::Platforms::<Name>::Service</tt>. Raises NameError when the
    # class does not exist.
    def service_class
      registered = self.class.registration(name)&.service
      return registered.to_s.constantize if registered

      "WarpEngine::Platforms::#{name.camelize}::Service".constantize
    end

    # Returns a new instance of #service_class.
    def service = service_class.new

    # Returns the human-readable platform name from the service class.
    def label = service_class.label

    # Returns the release asset kinds the platform produces.
    def expected_kinds = service_class.expected_kinds

    # Returns the expected kinds a release must have.
    def required_kinds = service_class.required_kinds & expected_kinds

    # Returns the expected kinds a release may lack.
    def optional_kinds = service_class.optional_kinds & expected_kinds

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
  end
end
