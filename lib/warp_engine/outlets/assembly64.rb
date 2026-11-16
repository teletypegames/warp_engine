require "json"

module WarpEngine
  module Outlets
    # The catalog as an Assembly64 server: the search API the C64 Ultimate
    # (and the 1541 Ultimate, the Ultimate 64) browses for programs, served
    # under <tt>/leet/search</tt> as Assembly64 itself serves it. A client
    # with a configurable server list (the Spiffy patch's
    # <tt>/flash/config/server.json</tt>) needs only the host name.
    #
    #   outlet :assembly64, type: :assembly64, platforms: %w[c64], kinds: %w[cartridge],
    #                       hosts: %w[a64.example.org], repo: "acme", repo_name: "Acme Games"
    #
    # Options:
    #
    # [platforms]        the platforms on offer (default <tt>["c64"]</tt>)
    # [kinds]            the asset kinds on offer (default <tt>["cartridge"]</tt>)
    # [statuses]         the statuses listed; empty for the default visible ones
    # [hosts]            the host names it answers; empty for any (+host+ takes one)
    # [repo]             the repository key in the +repo+ preset (default the outlet key)
    # [repo_name]        its display name (default <tt>"WarpEngine"</tt>)
    # [categories]       a Hash of catalog category key to Assembly64 category
    #                    (a key of CATEGORY_IDS); a category it does not name is
    #                    taken as is, then with an +s+ added, then as +default_category+
    # [default_category] the Assembly64 category of everything else (default +games+)
    # [client_ids]       the <tt>Client-Id</tt> header values it accepts; empty for any
    # [max_results]      the most results a search returns (default 100)
    # [name_length]      the longest file name, extension included (default 16)
    #
    # Endpoints (all GET, under the engine's mount):
    #
    # [<tt>/leet/search/aql/presets</tt>]                the search form's presets
    # [<tt>/leet/search/categories</tt>]                 the categories the result ids stand for
    # [<tt>/leet/search/aql?query=</tt>]                 a search, cut to fit LEGACY_BODY_LIMIT
    # [<tt>/leet/search/aql/START/COUNT?query=</tt>]     a page of a search
    # [<tt>/leet/search/entries/ID/CATEGORY</tt>]        the files of a title
    # [<tt>/leet/search/bin/ID/CATEGORY/FILE</tt>]       one file
    #
    # Only anonymous, ungated titles are on offer (WarpEngine::Catalog::Offer);
    # a file goes out through WarpEngine::DownloadService, so the access policy
    # sees it and it is counted. The outlet reads its options and draws the
    # routes; Assembly64::Catalog answers the requests.
    class Assembly64 < Base
      include Served

      # The path the endpoints live under, as Assembly64 clients ask for them.
      PATH = "leet/search".freeze

      # The Assembly64 categories and the ids its results carry for them (the
      # CSDb subcategory ids of the real server's presets).
      CATEGORY_IDS = {
        "games" => 0, "demos" => 1, "c128" => 2, "graphics" => 3, "music" => 4, "mags" => 5,
        "bbs" => 6, "misc" => 7, "tools" => 8, "charts" => 9, "easyflash" => 10, "intros" => 11
      }.freeze

      # The display names of CATEGORY_IDS in the presets.
      CATEGORY_NAMES = {
        "games" => "Games", "demos" => "Demos", "c128" => "C128", "graphics" => "Graphics", "music" => "Music",
        "mags" => "Mags", "bbs" => "BBS", "misc" => "Misc", "tools" => "Tools", "charts" => "Charts",
        "easyflash" => "Easyflash", "intros" => "Intros"
      }.freeze

      # The periods of the +latest+ preset: aqlKey to display name.
      LATEST = {
        "1days" => "Day", "2days" => "2 days", "4days" => "4 days", "1week" => "Week", "2weeks" => "2 weeks",
        "3weeks" => "3 weeks", "1month" => "Month", "2months" => "2 months", "3months" => "3 months",
        "6months" => "6 months", "1year" => "Year", "2years" => "2 years"
      }.freeze

      # The orders of the +sort+ preset: aqlKey to display name.
      SORTS = { "name" => "Name", "group" => "Group", "year" => "Year" }.freeze

      # The query keys that narrow a search; a condition on any other key
      # (+handle+, +event+, +rating+) matches nothing, as no title here has one.
      FILTER_KEYS = %w[name group repo category subcat type date year latest].freeze

      # The query keys that order a search.
      ORDER_KEYS = %w[sort order].freeze

      # The largest JSON body of an unpaged search: the Ultimate firmware drops
      # a response over 16 KiB, so the list is cut to stay under it.
      LEGACY_BODY_LIMIT = 16_000

      # The form a +repo+ key must have.
      REPO_PATTERN = /\A[a-z0-9]{1,24}\z/

      # The options an Assembly64 outlet takes.
      OPTIONS = %i[platforms kinds statuses hosts host repo repo_name categories default_category client_ids
                   max_results name_length].freeze

      class << self
        # Returns +assembly64+.
        def type_name = "assembly64"

        # Draws the endpoints into the engine's routes (+mapper+), behind a
        # constraint that lets a request through only when a configured
        # outlet of the type answers it (WarpEngine::Outlets.serving).
        def draw_routes(mapper)
          constraint = ->(request) { WarpEngine::Outlets.serving(type_name, request).present? }
          mapper.constraints(constraint) do
            mapper.scope PATH, module: "outlets", as: "assembly64", format: false do
              mapper.get "aql/presets", to: "assembly64#presets", as: :presets
              mapper.get "categories", to: "assembly64#categories", as: :categories
              mapper.get "aql/:start/:count", to: "assembly64#search", as: :search_page,
                                              constraints: { start: /\d+/, count: /\d+/ }
              mapper.get "aql", to: "assembly64#search", as: :search
              mapper.get "entries/:id/:category", to: "assembly64#entries", as: :entries
              mapper.get "bin/:id/:category/:file", to: "assembly64#bin", as: :bin, constraints: { file: %r{[^/]+} }
            end
          end
        end
      end

      # Returns the platforms on offer.
      def platforms = option_list(:platforms).presence || %w[c64]

      # Returns the asset kinds on offer.
      def kinds = option_list(:kinds).presence || %w[cartridge]

      # Returns the WarpEngine::Catalog::Offer of the outlet.
      def offer
        @offer ||= WarpEngine::Catalog::Offer.new(platforms: platforms, kinds: kinds, statuses: option_list(:statuses))
      end

      # Returns the repository key of the +repo+ preset.
      def repo = (options[:repo].presence || key).to_s

      # Returns the repository's display name.
      def repo_name = (options[:repo_name].presence || "WarpEngine").to_s

      # Returns the most results one search returns.
      def max_results = Integer(options.fetch(:max_results, 100))

      # Returns the longest file name, extension included.
      def name_length = Integer(options.fetch(:name_length, 16))

      # Returns the accepted <tt>Client-Id</tt> values; empty for any.
      def client_ids = option_list(:client_ids)

      # Returns +true+ when a request with the <tt>Client-Id</tt> +client_id+ is
      # accepted.
      def client_allowed?(client_id) = client_ids.empty? || client_ids.include?(client_id.to_s)

      # Checks the option keys, platforms, kinds, categories, repository key
      # and limits. Raises ConfigurationError when one is invalid; returns +self+.
      def validate!
        check_keys!(OPTIONS)
        check_platforms!(platforms)
        check_kinds!(kinds)
        raise ConfigurationError, "#{key}: repo must match #{REPO_PATTERN.inspect}" unless repo.match?(REPO_PATTERN)

        unknown = (category_map.values + [ default_category ]) - CATEGORY_IDS.keys
        raise ConfigurationError, "#{key}: unknown Assembly64 category #{unknown.first.inspect}" if unknown.any?
        raise ConfigurationError, "#{key}: max_results must be positive" unless max_results.positive?
        raise ConfigurationError, "#{key}: name_length leaves no room for a name" unless name_length > 4

        self
      rescue ArgumentError, TypeError => e
        raise ConfigurationError, "#{key}: #{e.message}"
      end

      # Returns the Base#descriptor with the +hosts+, the +path+ of the
      # endpoints and the +repo+.
      def descriptor = super.merge(hosts: hosts, path: "/#{PATH}", repo: repo)

      # Returns the Assembly64::Catalog of the outlet: what its endpoints answer.
      def catalog = Catalog.new(self)

      # Returns the Assembly64 category (a key of CATEGORY_IDS) of the catalog
      # category +category+: the one +categories+ names, else the category as
      # is or with an +s+ added when Assembly64 has it, else +default_category+.
      def aql_category(category)
        name = category.to_s.downcase
        return default_category if name.empty?

        category_map[name] || ([ name, "#{name}s" ] & CATEGORY_IDS.keys).first || default_category
      end

      private

      def category_map = options[:categories].to_h.to_h { |from, to| [ from.to_s, to.to_s ] }

      def default_category = (options[:default_category].presence || "games").to_s
    end
  end
end

require "warp_engine/outlets/assembly64/query"
require "warp_engine/outlets/assembly64/catalog"
