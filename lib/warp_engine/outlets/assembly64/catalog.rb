module WarpEngine
  module Outlets
    class Assembly64 < Base
      # What an Assembly64 outlet answers: the presets of the search form, a
      # search, the files of a title and one file of it, all drawn from the
      # outlet's WarpEngine::Catalog::Offer. The
      # WarpEngine::Outlets::Assembly64Controller renders them.
      class Catalog
        # The WarpEngine::Outlets::Assembly64 the catalog answers for.
        attr_reader :outlet

        # [outlet] the WarpEngine::Outlets::Assembly64
        def initialize(outlet)
          @outlet = outlet
        end

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
        # [count] the size of a page, capped at the outlet's +max_results+
        #
        # An unpaged search returns at most the outlet's +max_results+ results and is cut so
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
        # name as a shelf writes it (WarpEngine::Names.file_name), cut
        # to fit the outlet's +name_length+ with the extension in capitals
        # (<tt>ARIADNE.PRG</tt>); the software id when nothing of the name is left.
        def file_name(item)
          extension = item.extension.empty? ? "" : ".#{item.extension.upcase}"
          Names.file_name(item.software, length: outlet.name_length, extension: extension) || "#{item.software.id}#{extension}"
        end

        private

        delegate :offer, :repo, :repo_name, :max_results, :aql_category, to: :outlet

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
            name: Names.clean(software.title),
            group: Names.clean(software.author),
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
      end
    end
  end
end
