require "uri"

module WarpEngine
  # The store registry: the stores a graphical client (the WarpEngine Desktop)
  # offers to install on its first run, served at <tt>GET /api/stores</tt> as
  # name and catalog address pairs. A record says what a store is and nothing
  # about how it works; how a store behaves is fixed in each installed client.
  #
  # The registry is set with <tt>store_registry</tt> in the configuration:
  #
  # [+:own+ (default)]  this catalog alone, under <tt>store_name</tt> or the host name of its address
  # [an Array]          a fixed list: Hashes with +name+ and +catalog_url+, and +:own+ for this catalog
  # [+:none+]           no registry; <tt>GET /api/stores</tt> answers 404
  # [any other object]  a host adapter answering <tt>stores(catalog_url:)</tt> with Entry objects or
  #                     Hashes with +name+ and +catalog_url+ (e.g. read from the host's own table)
  #
  #   WarpEngine.configure do
  #     store_name "My Studio"
  #     store_registry [ :own, { name: "Friends' Games", catalog_url: "https://friends.example" } ]
  #   end
  module StoreRegistry
    # The +catalog_url+ an Entry must have: an absolute http or https address.
    URL = %r{\Ahttps?://\S+\z}

    # steep:ignore:start

    # One registry record: the display +name+ of a store and the +catalog_url+
    # of the WarpEngine catalog it serves.
    Entry = ::Data.define(:name, :catalog_url) do
      # Returns the record as the API serves it: <tt>{ name:, catalogUrl: }</tt>.
      def as_json(*) = { name: name, catalogUrl: catalog_url }
    end
    # steep:ignore:end

    # The default registry: this catalog and nothing else.
    class Own
      # Returns the one Entry of the catalog at +catalog_url+
      # (StoreRegistry.own_entry).
      def stores(catalog_url:)
        [ StoreRegistry.own_entry(catalog_url) ]
      end
    end

    # A registry written into the configuration as a list.
    class Fixed
      # The configured list: Hashes with +name+ and +catalog_url+, and +:own+.
      attr_reader :entries

      # Creates the registry from the configured +entries+.
      def initialize(entries)
        @entries = Array(entries)
      end

      # Returns the entries in their configured order, +:own+ replaced by this
      # catalog's Entry (StoreRegistry.own_entry for +catalog_url+).
      def stores(catalog_url:)
        entries.map do |entry|
          case entry
          when :own, "own" then StoreRegistry.own_entry(catalog_url)
          else entry
          end
        end
      end
    end

    class << self
      # Returns the configured registry object, or +nil+ when the registry is
      # off (+:none+, +false+). +nil+ and +:own+ give the shared Own instance,
      # an Array a Fixed registry.
      def current
        configured = WarpEngine.config.store_registry

        case configured
        when nil, :own, "own" then own_registry
        when :none, "none", false then nil
        when Array then Fixed.new(configured)
        else configured
        end
      end

      # Returns +true+ unless the registry is off.
      def enabled? = !current.nil?

      # Returns the registry of the catalog at +catalog_url+ (this deployment's
      # own address) as Entry objects; records without a name or an http(s)
      # catalog address are left out. Returns an empty Array when the registry
      # is off.
      def stores(catalog_url:)
        registry = current
        return [] if registry.nil?

        Array(registry.stores(catalog_url: catalog_url)).filter_map { |record| entry(record) }
      end

      # Returns the Entry of this catalog at +catalog_url+: named by
      # <tt>store_name</tt>, or by the host name of +catalog_url+ when that is
      # not set.
      def own_entry(catalog_url)
        name = WarpEngine.config.store_name.to_s.strip
        name = URI.parse(catalog_url).host.to_s if name.empty?
        Entry.new(name: name, catalog_url: catalog_url)
      end

      # Returns the memoized Own instance.
      def own_registry
        @own_registry ||= Own.new
      end

      # Drops the memoized Own instance.
      def reset!
        @own_registry = nil
      end

      private

      def entry(record)
        return record if record.is_a?(Entry) && valid?(record.name, record.catalog_url)
        return nil unless record.respond_to?(:to_h)

        values = record.to_h.transform_keys(&:to_s)
        name = values["name"].to_s.strip
        url = (values["catalog_url"] || values["catalogUrl"]).to_s.strip
        valid?(name, url) ? Entry.new(name: name, catalog_url: url) : nil
      end

      def valid?(name, url) = name.to_s.strip.present? && URL.match?(url.to_s)
    end
  end
end
