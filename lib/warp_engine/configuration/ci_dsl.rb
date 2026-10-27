module WarpEngine
  class Configuration
    # Builds a CI adapter: its connection settings, a `tools` image every
    # platform shares unless it names its own, and one `platform` line each.
    class CIDSL
      ADAPTERS = {
        woodpecker: "WarpEngine::CI::Woodpecker::Adapter",
        gitlab:     "WarpEngine::CI::Gitlab::Adapter"
      }.freeze

      SETTINGS = {
        woodpecker: %i[url api_token repo_owner public_key public_key_url update_server],
        gitlab:     %i[url api_token webhook_secret update_server]
      }.freeze

      PLATFORM_KEYS = %i[builder exporter tools web_shell bundle_id_prefix forge_release].freeze

      def self.build(kind, &block)
        builder = new(kind)
        builder.instance_eval(&block)
        builder.adapter
      end

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

      def tools(image) = @defaults[:tools] = image

      def platform(name, **spec)
        unknown = spec.keys - PLATFORM_KEYS
        raise ArgumentError, "unknown platform keys for #{name}: #{unknown.join(', ')}" if unknown.any?
        raise ArgumentError, "platform #{name} needs a builder" if spec[:builder].blank?

        @platforms[name.to_s] = @defaults.merge(spec)
      end

      def adapter
        ADAPTERS.fetch(@kind).constantize.new(**@settings, platforms: @platforms)
      end
    end
  end
end
