module WarpEngine
  class Platform
    BUILTIN = %w[tic80 ebitengine love c64 plus4 godot bevy phaser dos].freeze
    NAMES = BUILTIN

    FORMAT = /\A[a-z0-9_]{2,32}\z/

    Registration = Struct.new(:name, :service, :built_kinds, :templates, keyword_init: true)

    class << self
      def names = BUILTIN + (registrations.keys - BUILTIN)

      def all = names.map { |name| new(name) }

      def exists?(name) = names.include?(name.to_s)

      def builtin?(name) = BUILTIN.include?(name.to_s)

      def find(name)
        return nil unless exists?(name)

        new(name.to_s)
      end

      def find!(name)
        find(name) || raise(ArgumentError, "Unsupported platform: #{name}")
      end

      def registration(name) = registrations[name.to_s]

      def registrations = WarpEngine.config.platforms
    end

    attr_reader :name

    def initialize(name)
      @name = name.to_s
    end

    def service_class
      registered = self.class.registration(name)&.service
      return registered.to_s.constantize if registered

      "WarpEngine::Platforms::#{name.camelize}::Service".constantize
    end

    def service = service_class.new

    def label = service_class.label

    def expected_kinds = service_class.expected_kinds

    def required_kinds = service_class.required_kinds & expected_kinds

    def optional_kinds = service_class.optional_kinds & expected_kinds

    def to_s = name

    def ==(other)
      other.is_a?(Platform) ? name == other.name : name == other.to_s
    end
    alias eql? ==

    def hash = name.hash
  end
end
