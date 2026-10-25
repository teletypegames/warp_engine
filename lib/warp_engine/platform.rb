module WarpEngine
  class Platform
    NAMES = %w[tic80 ebitengine love c64 plus4 godot bevy phaser dos].freeze

    class << self
      def names = NAMES

      def all = NAMES.map { |name| new(name) }

      def exists?(name) = NAMES.include?(name.to_s)

      def find(name)
        return nil unless exists?(name)

        new(name.to_s)
      end

      def find!(name)
        find(name) || raise(ArgumentError, "Unsupported platform: #{name}")
      end
    end

    attr_reader :name

    def initialize(name)
      @name = name.to_s
    end

    def service_class
      "WarpEngine::Platforms::#{name.camelize}::Service".constantize
    end

    def service = service_class.new

    def label = service_class.label

    def expected_kinds = service_class.expected_kinds

    def to_s = name

    def ==(other)
      other.is_a?(Platform) ? name == other.name : name == other.to_s
    end
    alias eql? ==

    def hash = name.hash
  end
end
