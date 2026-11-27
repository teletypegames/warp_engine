require "warp_engine/feeds/base"
require "warp_engine/names"
require "warp_engine/feeds/wecp"
require "warp_engine/feeds/directory"
require "warp_engine/feeds/assembly64"

module WarpEngine
  # Feeds: the formats the catalog leaves the engine in. Three layers make up
  # the way out:
  #
  # 1. the models and the seams (storage, access policy, images);
  # 2. the selection, WarpEngine::Catalog::Selection: which titles, which release,
  #    which file;
  # 3. the feeds, each presenting a selection in one format.
  #
  # The builtin types:
  #
  # [+wecp+]       WarpEngine::Feeds::Wecp, the JSON catalog API; always on,
  #                not configured, and not on a selection (dynamic)
  # [+directory+]  WarpEngine::Feeds::Directory, a folder with an INDEX.TXT (static)
  # [+assembly64+] WarpEngine::Feeds::Assembly64, the Assembly64 search API the
  #                C64 Ultimate browses (dynamic)
  #
  # Every type has the same shape: lib/warp_engine/feeds/TYPE.rb holds the
  # feed class (options, checks, descriptor, routes or sync), the folder
  # beside it the objects that do the work, and a dynamic type's controller
  # lives in app/controllers/warp_engine (the catalog API's under +api+, the
  # others' under +feeds+).
  #
  # A host configures feeds in WarpEngine.configure (a directory is a feed of
  # the type +directory+, +directory+ the short form) and may register types of its own:
  #
  #   directory :c64, kind: "package", path: "directories/C64", extension: ".PRG"
  #   feed :assembly64, type: :assembly64, platforms: %w[c64], hosts: %w[a64.example.org]
  #   register_feed_type :acme, "Acme::CustomFeed"
  module Feeds
    # The builtin feed types a definition may name, by type name (the
    # catalog API, Wecp, is always on and cannot be configured).
    TYPES = {
      "directory"  => "WarpEngine::Feeds::Directory",
      "assembly64" => "WarpEngine::Feeds::Assembly64"
    }.freeze

    # The form a feed key must have.
    KEY_PATTERN = /\A[a-z0-9_]{1,32}\z/

    class << self
      # Returns the feed types as a Hash of type name to class name: TYPES
      # and the types the host registered.
      def types = TYPES.merge(WarpEngine.config.feed_types)

      # Returns the class of the type +name+. Raises ConfigurationError for an
      # unknown type.
      def type_class(name)
        class_name = types[name.to_s]
        raise ConfigurationError, "unknown feed type: #{name.inspect}" if class_name.nil?

        class_name.constantize
      end

      # Returns every configured feed: the WarpEngine::Feeds::Wecp feed,
      # then the definitions in WarpEngine.config.feeds, in their order.
      # Raises ConfigurationError on an unknown type or a malformed key.
      def all
        [ Wecp.new ] + Array(WarpEngine.config.feeds).map { |definition| build(definition) }
      end

      # Returns the feed configured under +key+, or +nil+.
      def [](key) = all.find { |feed| feed.key == key.to_s }

      # Returns the feeds of the static types (they write files).
      def static = all.select { |feed| feed.class.static? }

      # Returns +true+ when any feed but the catalog API is configured.
      def any? = Array(WarpEngine.config.feeds).any?

      # Builds and checks every feed (Base#validate!), then what the feeds
      # of each type must agree on (Base.validate_all!). Raises
      # ConfigurationError on an invalid definition, two feeds with one key
      # or a dynamic type without +draw_routes+. Returns the feeds.
      def validate!
        feeds = all.each(&:validate!)
        duplicate = feeds.map(&:key).tally.find { |_, count| count > 1 }&.first
        raise ConfigurationError, "two feeds share the key #{duplicate}" if duplicate

        feeds.group_by(&:class).each do |klass, group|
          raise ConfigurationError, "#{klass.name} is dynamic but draws no routes" if klass.dynamic? && !klass.respond_to?(:draw_routes)

          klass.validate_all!(group)
        end
        feeds
      end

      # Brings the static feeds carrying +platform+ (all of them when
      # +nil+) in line with the catalog, each through its +sync!+. A feed
      # that fails is logged and left out. Returns the sync results; an empty
      # Array when nothing is configured or the configuration is invalid.
      def refresh(platform: nil)
        return [] unless any?

        targets(platform).filter_map do |feed|
          feed.sync!
        rescue StandardError => e
          Rails.logger.error("[WarpEngine::Feeds] refresh #{feed.key}: #{e.class}: #{e.message}")
          nil
        end
      rescue WarpEngine::ConfigurationError => e
        Rails.logger.error("[WarpEngine::Feeds] refresh #{platform || 'all'}: #{e.message}")
        []
      end

      # Returns the descriptor of every feed (Base#descriptor), as
      # <tt>GET /api/service</tt> lists them under +feeds+; only the catalog
      # API's when the configuration is invalid.
      def descriptors
        all.map(&:descriptor)
      rescue WarpEngine::ConfigurationError
        [ Wecp.new.descriptor ]
      end

      # Returns the first configured feed of the type +type_name+ that
      # answers +request+ (WarpEngine::Feeds::Dynamic#serves?), or +nil+.
      def serving(type_name, request)
        all.find { |feed| feed.type == type_name.to_s && feed.class.dynamic? && feed.serves?(request) }
      rescue ConfigurationError
        nil
      end

      # Draws the routes of every dynamic feed type into the engine's route
      # set (+mapper+), each type once, through its +draw_routes+: the catalog
      # API (Wecp) first, then the builtin and registered types.
      def draw_routes(mapper)
        classes = [ Wecp ] + types.values.filter_map(&:safe_constantize)
        classes.uniq.each do |klass|
          klass.draw_routes(mapper) if klass.dynamic? && klass.respond_to?(:draw_routes)
        end
      end

      private

      def targets(platform)
        feeds = static
        return feeds if platform.nil?

        feeds.select { |feed| feed.platforms.empty? || feed.platforms.include?(platform.to_s) }
      end

      def build(definition)
        attributes = definition.to_h.symbolize_keys
        key = attributes.delete(:key).to_s
        raise ConfigurationError, "feed key must match #{KEY_PATTERN.inspect}: #{key.inspect}" unless key.match?(KEY_PATTERN)

        type_class(attributes.delete(:type)).new(key, attributes)
      end
    end
  end
end
