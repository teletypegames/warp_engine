require "warp_engine/outlets/base"
require "warp_engine/names"
require "warp_engine/outlets/wecp"
require "warp_engine/outlets/shelf"
require "warp_engine/outlets/assembly64"

module WarpEngine
  # Outlets: the formats the catalog leaves the engine in. Three layers make up
  # the way out:
  #
  # 1. the models and the seams (storage, access policy, images);
  # 2. the offer, WarpEngine::Catalog::Offer: which titles, which release,
  #    which file;
  # 3. the outlets, each presenting an offer in one format.
  #
  # The builtin types:
  #
  # [+wecp+]       WarpEngine::Outlets::Wecp, the JSON catalog API; always on,
  #                not configured, and not on an offer (served)
  # [+shelf+]      WarpEngine::Outlets::Shelf, a folder with an INDEX.TXT (materialized)
  # [+assembly64+] WarpEngine::Outlets::Assembly64, the Assembly64 search API the
  #                C64 Ultimate browses (served)
  #
  # Every type has the same shape: lib/warp_engine/outlets/TYPE.rb holds the
  # outlet class (options, checks, descriptor, routes or sync), the folder
  # beside it the objects that do the work, and a served type's controller
  # lives in app/controllers/warp_engine (the catalog API's under +api+, the
  # others' under +outlets+).
  #
  # A host configures outlets in WarpEngine.configure (a shelf is an outlet of
  # the type +shelf+, +shelf+ the short form) and may register types of its own:
  #
  #   shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG"
  #   outlet :assembly64, type: :assembly64, platforms: %w[c64], hosts: %w[a64.example.org]
  #   register_outlet_type :acme, "Acme::FeedOutlet"
  module Outlets
    # The builtin outlet types a definition may name, by type name (the
    # catalog API, Wecp, is always on and cannot be configured).
    TYPES = {
      "shelf"      => "WarpEngine::Outlets::Shelf",
      "assembly64" => "WarpEngine::Outlets::Assembly64"
    }.freeze

    # The form an outlet key must have.
    KEY_PATTERN = /\A[a-z0-9_]{1,32}\z/

    class << self
      # Returns the outlet types as a Hash of type name to class name: TYPES
      # and the types the host registered.
      def types = TYPES.merge(WarpEngine.config.outlet_types)

      # Returns the class of the type +name+. Raises ConfigurationError for an
      # unknown type.
      def type_class(name)
        class_name = types[name.to_s]
        raise ConfigurationError, "unknown outlet type: #{name.inspect}" if class_name.nil?

        class_name.constantize
      end

      # Returns every configured outlet: the WarpEngine::Outlets::Wecp outlet,
      # then the definitions in WarpEngine.config.outlets, in their order.
      # Raises ConfigurationError on an unknown type or a malformed key.
      def all
        [ Wecp.new ] + Array(WarpEngine.config.outlets).map { |definition| build(definition) }
      end

      # Returns the outlet configured under +key+, or +nil+.
      def [](key) = all.find { |outlet| outlet.key == key.to_s }

      # Returns the outlets of the materialized types (they write files).
      def materialized = all.select { |outlet| outlet.class.materialized? }

      # Returns +true+ when any outlet but the catalog API is configured.
      def any? = Array(WarpEngine.config.outlets).any?

      # Builds and checks every outlet (Base#validate!), then what the outlets
      # of each type must agree on (Base.validate_all!). Raises
      # ConfigurationError on an invalid definition, two outlets with one key
      # or a served type without +draw_routes+. Returns the outlets.
      def validate!
        outlets = all.each(&:validate!)
        duplicate = outlets.map(&:key).tally.find { |_, count| count > 1 }&.first
        raise ConfigurationError, "two outlets share the key #{duplicate}" if duplicate

        outlets.group_by(&:class).each do |klass, group|
          raise ConfigurationError, "#{klass.name} is served but draws no routes" if klass.served? && !klass.respond_to?(:draw_routes)

          klass.validate_all!(group)
        end
        outlets
      end

      # Brings the materialized outlets carrying +platform+ (all of them when
      # +nil+) in line with the catalog, each through its +sync!+. An outlet
      # that fails is logged and left out. Returns the sync results; an empty
      # Array when nothing is configured or the configuration is invalid.
      def refresh(platform: nil)
        return [] unless any?

        targets(platform).filter_map do |outlet|
          outlet.sync!
        rescue StandardError => e
          Rails.logger.error("[WarpEngine::Outlets] refresh #{outlet.key}: #{e.class}: #{e.message}")
          nil
        end
      rescue WarpEngine::ConfigurationError => e
        Rails.logger.error("[WarpEngine::Outlets] refresh #{platform || 'all'}: #{e.message}")
        []
      end

      # Returns the descriptor of every outlet (Base#descriptor), as
      # <tt>GET /api/service</tt> lists them under +outlets+; only the catalog
      # API's when the configuration is invalid.
      def descriptors
        all.map(&:descriptor)
      rescue WarpEngine::ConfigurationError
        [ Wecp.new.descriptor ]
      end

      # Returns the first configured outlet of the type +type_name+ that
      # answers +request+ (WarpEngine::Outlets::Served#serves?), or +nil+.
      def serving(type_name, request)
        all.find { |outlet| outlet.type == type_name.to_s && outlet.class.served? && outlet.serves?(request) }
      rescue ConfigurationError
        nil
      end

      # Draws the routes of every served outlet type into the engine's route
      # set (+mapper+), each type once, through its +draw_routes+: the catalog
      # API (Wecp) first, then the builtin and registered types.
      def draw_routes(mapper)
        classes = [ Wecp ] + types.values.filter_map(&:safe_constantize)
        classes.uniq.each do |klass|
          klass.draw_routes(mapper) if klass.served? && klass.respond_to?(:draw_routes)
        end
      end

      private

      def targets(platform)
        outlets = materialized
        return outlets if platform.nil?

        outlets.select { |outlet| outlet.platforms.empty? || outlet.platforms.include?(platform.to_s) }
      end

      def build(definition)
        attributes = definition.to_h.symbolize_keys
        key = attributes.delete(:key).to_s
        raise ConfigurationError, "outlet key must match #{KEY_PATTERN.inspect}: #{key.inspect}" unless key.match?(KEY_PATTERN)

        type_class(attributes.delete(:type)).new(key, attributes)
      end
    end
  end
end
