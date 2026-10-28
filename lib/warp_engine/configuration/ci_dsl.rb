module WarpEngine
  class Configuration
    # Builds a CI adapter: its connection settings, a +tools+ image every
    # platform shares unless it names its own, and one +platform+ line each.
    #
    #   ci :woodpecker do
    #     url       ENV["WOODPECKER_URL"]
    #     api_token ENV["WOODPECKER_API_TOKEN"]
    #     platform :godot, builder: "registry.example/godot-builder:4.6"
    #   end
    #
    # Every connection setting (+url+, +api_token+, +repo_owner+, +public_key+,
    # +public_key_url+, +update_server+, +webhook_secret+) is a method taking the
    # value; it raises ArgumentError when the chosen adapter has no such setting.
    class CIDSL
      # The adapter kinds and the class each builds.
      ADAPTERS = {
        woodpecker: "WarpEngine::CI::Woodpecker::Adapter",
        gitlab:     "WarpEngine::CI::Gitlab::Adapter"
      }.freeze

      # The connection settings each adapter kind accepts.
      SETTINGS = {
        woodpecker: %i[url api_token repo_owner public_key public_key_url update_server],
        gitlab:     %i[url api_token webhook_secret update_server]
      }.freeze

      # The keys a +platform+ line accepts.
      PLATFORM_KEYS = %i[builder exporter tools web_shell bundle_id_prefix forge_release].freeze

      # Evaluates +block+ for the adapter +kind+ and returns the built adapter.
      def self.build(kind, &block)
        builder = new(kind)
        builder.instance_eval(&block)
        builder.adapter
      end

      # Creates a builder for the adapter +kind+ (+:woodpecker+ or +:gitlab+).
      # Raises ArgumentError for any other kind.
      def initialize(kind)
        @kind = kind.to_sym
        raise ArgumentError, "unknown CI adapter: #{kind.inspect} (#{ADAPTERS.keys.join(', ')})" unless ADAPTERS.key?(@kind)

        @settings  = {}
        @defaults  = {}
        @platforms = {}
      end

      SETTINGS.values.flatten.uniq.each do |name|
        define_method(name) do |value|
          raise ArgumentError, "the #{@kind} adapter takes no #{name}" unless SETTINGS[@kind].include?(name)

          @settings[name] = value
        end
      end

      # Sets the default +tools+ image of every platform that names none.
      def tools(image) = @defaults[:tools] = image

      # Configures one platform for the adapter; +spec+ takes the PLATFORM_KEYS,
      # +builder+ being required. Raises ArgumentError on an unknown key or a
      # missing builder.
      def platform(name, **spec)
        unknown = spec.keys - PLATFORM_KEYS
        raise ArgumentError, "unknown platform keys for #{name}: #{unknown.join(', ')}" if unknown.any?
        raise ArgumentError, "platform #{name} needs a builder" if spec[:builder].blank?

        @platforms[name.to_s] = @defaults.merge(spec)
      end

      # Returns a new adapter instance built from the collected settings and
      # platforms.
      def adapter
        ADAPTERS.fetch(@kind).constantize.new(**@settings, platforms: @platforms)
      end
    end
  end
end
