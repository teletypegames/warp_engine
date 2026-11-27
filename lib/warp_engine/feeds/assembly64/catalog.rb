module WarpEngine
  module Feeds
    class Assembly64 < Base
      # What an Assembly64 feed answers: the presets of the search form, a
      # search, the files of a title and one file of it, all drawn from the
      # feed's WarpEngine::Catalog::Selection. The
      # WarpEngine::Feeds::Assembly64Controller renders them.
      class Catalog
        # The WarpEngine::Feeds::Assembly64 the catalog answers for.
        attr_reader :feed

        # [feed] the WarpEngine::Feeds::Assembly64
        def initialize(feed)
          @feed = feed
        end

        # Returns the presets of the search form, in the order the client shows
        # them: +repo+, +category+ (the categories in the selection), +type+ (the file
        # types in the selection), +date+ (the years of the releases in the selection),
        # +latest+, +sort+ and +order+. Each is a Hash of +type+, +description+
        # and +values+ (+aqlKey+ and +name+).
        def presets
          rows = all_rows
          [
            preset("repo", "Repository", [ [ repo, repo_name ] ]),
            preset("category", "Category", offered_categories(rows).map { |aql| [ aql, CATEGORY_NAMES[aql], CATEGORY_IDS[aql] ] }),
            preset("type", "Type", rows.flat_map { |row| row[:types] }.uniq.sort.map { |type| [ type, nil ] }),
            preset("date", "Date", rows.map { |row| row[:year] }.uniq.sort.map { |year| [ year.to_s, nil ] }),
            preset("latest", "Latest", LATEST.to_a),
            preset("sort", "Sort by", SORTS.to_a),
            preset("order", "Sort Order", [ %w[asc Ascending], %w[desc Descending] ])
          ]
        end

        # Returns the categories in the selection, the ones a result's +category+ id
        # stands for, as Hashes of +id+, +name+ (the aqlKey) and +description+
        # (the display name) as the reference server answers them, with the
        # real server's +groupingName+ and +type+ (the repository key).
        def categories
          offered_categories(all_rows).map do |aql|
            name = CATEGORY_NAMES.fetch(aql)
            { id: CATEGORY_IDS.fetch(aql), name: aql, description: name, groupingName: name, type: repo }
          end
        end

        # Runs the AQL search +text+ and returns the results as Hashes of +id+
        # (a String), +name+, +group+, +year+, +released+
        # (<tt>YYYY-MM-DD</tt>), +category+ (an Integer), +rating+ (0),
        # +updated+ and +type+, one a title, the empty ones left out.
        #
        # [text]  the AQL query (see WarpEngine::Feeds::Assembly64::Query)
        # [start] the offset of a page, or +nil+ for an unpaged search
        # [count] the size of a page, capped at the feed's +max_results+
        #
        # An unpaged search returns at most the feed's +max_results+ results and is cut so
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

        # Returns the details of the title +id+ as the reference server's
        # metadata answers them: a Hash of +name+, +group+, +rating+ (0),
        # +released+ and +updated+ (<tt>YYYY-MM-DD HH:MM:SS</tt>, the release
        # offered), the empty ones left out; +nil+ when the title is not in the selection.
        def metadata(id)
          row = row_of(id)
          return nil if row.nil?

          software = row[:software]
          stamp = row[:release].created_at&.utc&.strftime("%Y-%m-%d %H:%M:%S")
          { name: Names.clean(software.title), group: Names.clean(software.author), rating: 0,
            released: stamp, updated: stamp }.compact_blank
        end

        # Returns the default image of the title +id+ (its default gallery
        # image, else its first) as a Hash of +path+ (the file, when the image
        # adapter gives one; see WarpEngine::Images.file_path_for) and +url+;
        # +nil+ when the title is not in the selection or has no image.
        def screenshot(id)
          row = row_of(id)
          images = row ? row[:software].software_images : []
          image = images.detect(&:is_default?) || images.first
          return nil if image.nil?

          { path: Images.file_path_for(image.image_id), url: Images.url_for(image.image_id) }
        end

        # Returns the files of the title +id+ as the +entries+ endpoint answers:
        # a Hash with +contentEntry+, one Hash a file (+path+, the file name;
        # +id+, its index; +size+; +date+, the release time in milliseconds), or
        # +nil+ when the title is not in the selection.
        def entries(id)
          items = items_of(id)
          return nil if items.empty?

          {
            contentEntry: items.each_with_index.map do |item, index|
              { path: file_name(item), id: index, size: item.size, date: (item.release.created_at.to_f * 1000).to_i }
            end,
            isContentByItself: false
          }
        end

        # Returns the WarpEngine::Catalog::Selection::Item of the title +id+ whose file
        # name (#file_name) is +file+, ignoring case, or whose +entries+ id is
        # +file+ when it is a number; +nil+ when there is none.
        def item(id, file)
          items = items_of(id)
          return items[file.to_i] if file.to_s.match?(/\A\d+\z/)

          items.find { |candidate| file_name(candidate).casecmp?(file.to_s) }
        end

        # Returns the file name of +item+ in the listing: the software's
        # name as a directory writes it (WarpEngine::Names.file_name), cut
        # to fit the feed's +name_length+ with the extension in capitals
        # (<tt>ARIADNE.PRG</tt>); the software id when nothing of the name is left.
        def file_name(item)
          extension = item.extension.empty? ? "" : ".#{item.extension.upcase}"
          Names.file_name(item.software, length: feed.name_length, extension: extension) || "#{item.software.id}#{extension}"
        end

        private

        delegate :selection, :repo, :repo_name, :max_results, :aql_category, to: :feed

        def items_of(id)
          id.to_s.match?(/\A\d+\z/) ? selection.items_of(id.to_i) : []
        end

        def row_of(id) = all_rows.find { |candidate| candidate[:software].id.to_s == id.to_s }

        def offered_categories(rows) = rows.map { |row| row[:aql_category] }.uniq.sort_by { |aql| CATEGORY_IDS.fetch(aql) }

        def all_rows
          selection.items.group_by(&:software).map do |software, items|
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
          created = (row[:release].created_at || Time.current).utc
          {
            id: software.id.to_s,
            name: Names.clean(software.title),
            group: Names.clean(software.author),
            year: row[:year],
            released: created.strftime("%Y-%m-%d"),
            category: CATEGORY_IDS.fetch(row[:aql_category]),
            rating: 0,
            updated: created.strftime("%Y-%m-%d %H:%M:%S"),
            type: row[:types].first.to_s
          }.compact_blank
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
          when "name"              then value == NAME_WILDCARD || [ software.title, software.name, software.directory_name ].compact.any? { |text| text.downcase.include?(value) }
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
          when "updated" then rows.sort_by { |row| [ row[:release].created_at || Time.at(0), row[:software].id ] }
          else rows.sort_by { |row| [ row[:software].title.downcase, row[:software].id ] }
          end
          query["order"].to_s.downcase == "desc" ? sorted.reverse : sorted
        end

        def preset(type, description, values)
          { type: type, description: description, values: values.map { |aql, name, id| { id: id, aqlKey: aql, name: name }.compact } }
        end
      end
    end
  end
end
