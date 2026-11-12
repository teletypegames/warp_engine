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
    # [<tt>/leet/search/aql?query=</tt>]                 a search, cut to fit LEGACY_BODY_LIMIT
    # [<tt>/leet/search/aql/START/COUNT?query=</tt>]     a page of a search
    # [<tt>/leet/search/entries/ID/CATEGORY</tt>]        the files of a title
    # [<tt>/leet/search/bin/ID/CATEGORY/FILE</tt>]       one file
    #
    # Only anonymous, ungated titles are on offer (WarpEngine::Catalog::Offer);
    # a file goes out through WarpEngine::DownloadService, so the access policy
    # sees it and it is counted.
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

      # Checks the platforms, kinds, categories, repository key and limits.
      # Raises ConfigurationError when one is invalid; returns +self+.
      def validate!
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

      # Returns the presets of the search form, in the order the client shows
      # them: +repo+, +category+ (the categories on offer), +type+ (the file
      # types on offer), +date+ (the years of the releases on offer),
      # +latest+, +sort+ and +order+. Each is a Hash of +type+, +description+
      # and +values+ (+aqlKey+ and +name+).
      def presets
        rows = all_rows
        [
          preset("repo", "Repository", [ [ repo, repo_name ] ]),
          preset("category", "Category", rows.map { |row| row[:aql_category] }.uniq.sort.map { |aql| [ aql, CATEGORY_NAMES[aql] ] }),
          preset("type", "Type", rows.flat_map { |row| row[:types] }.uniq.sort.map { |type| [ type, nil ] }),
          preset("date", "Date", rows.map { |row| row[:year] }.uniq.sort.map { |year| [ year.to_s, nil ] }),
          preset("latest", "Latest", LATEST.to_a),
          preset("sort", "Sort by", SORTS.to_a),
          preset("order", "Sort Order", [ %w[asc Ascending], %w[desc Descending] ])
        ]
      end

      # Runs the AQL search +text+ and returns the results as Hashes of +id+
      # (a String), +name+, +group+, +year+, +category+ (an Integer), +updated+
      # and +type+, one a title.
      #
      # [text]  the AQL query (see WarpEngine::Outlets::Assembly64::Query)
      # [start] the offset of a page, or +nil+ for an unpaged search
      # [count] the size of a page, capped at #max_results
      #
      # An unpaged search returns at most #max_results results and is cut so
      # that its JSON stays under LEGACY_BODY_LIMIT bytes.
      def search(text, start: nil, count: nil)
        query = Query.parse(text)
        rows = order(all_rows.select { |row| match?(row, query) }, query)

        if start.nil?
          results = rows.first(max_results).map { |row| result(row) }
          results.pop while results.any? && results.to_json.bytesize > LEGACY_BODY_LIMIT
          results
        else
          rows.drop(start.to_i).first([ count.to_i, max_results ].min).map { |row| result(row) }
        end
      end

      # Returns the files of the title +id+ as the +entries+ endpoint answers:
      # a Hash with +contentEntry+, one Hash a file (+path+, the file name;
      # +id+, its index; +size+; +date+, the release time in milliseconds), or
      # +nil+ when the title is not on offer.
      def entries(id)
        items = items_of(id)
        return nil if items.empty?

        {
          contentEntry: items.each_with_index.map do |item, index|
            { path: file_name(item), id: index, size: item.size, date: (item.release.created_at.to_f * 1000).to_i }
          end
        }
      end

      # Returns the WarpEngine::Catalog::Offer::Item of the title +id+ whose file
      # name (#file_name) is +file+, ignoring case, or +nil+.
      def item(id, file) = items_of(id).find { |candidate| file_name(candidate).casecmp?(file.to_s) }

      # Returns the file name of +item+ in the listing: the software's
      # +shelf_name+ or +name+, normalized as on a shelf
      # (WarpEngine::Shelves.normalize_name), cut to fit #name_length with the
      # extension, plus the extension in capitals (<tt>ARIADNE.PRG</tt>).
      def file_name(item)
        extension = item.extension.empty? ? "" : ".#{item.extension.upcase}"
        base = WarpEngine::Shelves.normalize_name(item.software.shelf_name.presence || item.software.name)
        base = base[0, name_length - extension.length].sub(/-+\z/, "")
        "#{base.presence || item.software.id}#{extension}"
      end

      private

      def items_of(id)
        id.to_s.match?(/\A\d+\z/) ? offer.items_of(id.to_i) : []
      end

      def all_rows
        offer.items.group_by(&:software).map do |software, items|
          release = items.map(&:release).max_by { |candidate| [ candidate.created_at || Time.at(0), candidate.id ] }
          aql = aql_category(software.category)
          {
            software: software, items: items, release: release, year: (release.created_at || Time.current).year,
            aql_category: aql, types: items.map(&:extension).reject(&:empty?).uniq
          }
        end
      end

      def result(row)
        software = row[:software]
        {
          id: software.id.to_s,
          name: WarpEngine::ShelfService.clean(software.title),
          group: WarpEngine::ShelfService.clean(software.author),
          year: row[:year],
          category: CATEGORY_IDS.fetch(row[:aql_category]),
          updated: (row[:release].created_at || Time.current).utc.strftime("%Y-%m-%d %H:%M:%S"),
          type: row[:types].first.to_s
        }
      end

      def match?(row, query)
        query.conditions.all? do |name, value|
          next true if ORDER_KEYS.include?(name)
          next false unless FILTER_KEYS.include?(name)

          matches?(row, name, value.downcase)
        end
      end

      def matches?(row, name, value)
        software = row[:software]
        case name
        when "name"              then [ software.title, software.name, software.shelf_name ].compact.any? { |text| text.downcase.include?(value) }
        when "group"             then software.author.to_s.downcase.include?(value)
        when "repo"              then value == repo
        when "category", "subcat" then value == row[:aql_category]
        when "type"              then row[:types].include?(value)
        when "date", "year"      then value == row[:year].to_s
        else latest?(row[:release], value)
        end
      end

      def latest?(release, value)
        amount, unit = value.match(/\A(\d+)(day|week|month|year)s?\z/)&.captures
        return false if amount.nil? || release.created_at.nil?

        release.created_at >= amount.to_i.public_send(unit).ago
      end

      def order(rows, query)
        sorted = case query["sort"]
        when "group" then rows.sort_by { |row| [ row[:software].author.to_s.downcase, row[:software].title.downcase ] }
        when "year"  then rows.sort_by { |row| [ row[:year], row[:software].title.downcase ] }
        else rows.sort_by { |row| [ row[:software].title.downcase, row[:software].id ] }
        end
        query["order"].to_s.downcase == "desc" ? sorted.reverse : sorted
      end

      def preset(type, description, values)
        { type: type, description: description, values: values.map { |aql, name| name ? { aqlKey: aql, name: name } : { aqlKey: aql } } }
      end

      def category_map = options[:categories].to_h.to_h { |from, to| [ from.to_s, to.to_s ] }

      def default_category = (options[:default_category].presence || "games").to_s

      def aql_category(category)
        key = category.to_s.downcase
        return default_category if key.empty?

        category_map[key] || ([ key, "#{key}s" ] & CATEGORY_IDS.keys).first || default_category
      end
    end
  end
end

require "warp_engine/outlets/assembly64/query"
