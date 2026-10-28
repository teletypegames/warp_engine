module WarpEngine
  # The catalog read API: the paged software list, its facet counts and the
  # status and category vocabulary, all limited to what the access policy shows
  # the subject.
  class SoftwareService
    include SoftwareResponseBuilder

    # The orders #index accepts by name: +title+ (default), +updated+ and +newest+.
    SORTS = {
      "title"   => [ Arel.sql("LOWER(softwares.title) ASC"), Arel.sql("softwares.id ASC") ],
      "updated" => [ Arel.sql("softwares.updated_at DESC"), Arel.sql("softwares.id DESC") ],
      "newest"  => [ Arel.sql("softwares.created_at DESC"), Arel.sql("softwares.id DESC") ]
    }.freeze

    # Returns a page of the catalog as a Hash: +api+ (WarpEngine::API_VERSION),
    # +page+, +perPage+, +total+, +totalPages+, +nextPage+ (+nil+ on the last
    # page) and +softwares+, the catalog entries.
    #
    # [owner_id]  only the softwares of this owner
    # [subject]   the caller, or +nil+ when anonymous
    # [page]      the page number (from 1); without it and +per_page+ every software is on one page
    # [per_page]  the page size, clamped to <tt>WarpEngine.config.catalog_max_page_size</tt>;
    #             defaults to <tt>catalog_page_size</tt> when +page+ is given
    # [statuses]  only these statuses
    # [platform]  only this platform
    # [category]  only this category
    # [query]     a search text
    # [sort]      a key of SORTS
    def index(owner_id: nil, subject: nil, page: nil, per_page: nil, statuses: [], platform: nil, category: nil, query: nil, sort: nil)
      scope = filtered(visible_scope(subject), owner_id: owner_id, statuses: statuses, platform: platform, category: category, query: query)
      total = scope.count
      per = page_size(per_page, total, paged: !page.nil?)
      current = [ page.to_i, 1 ].max
      pages = per.zero? ? 1 : [ (total.to_f / per).ceil, 1 ].max

      softwares = scope.includes(releases: [ :release_assets ])
                       .includes(:external_links, :software_images)
                       .order(*SORTS.fetch(sort.to_s, SORTS["title"]))
                       .offset((current - 1) * per)
                       .limit(per)
                       .to_a
      counts = download_counts_for(softwares.flat_map { |sw| sw.releases.map(&:id) })

      {
        api:        WarpEngine::API_VERSION,
        page:       current,
        perPage:    per,
        total:      total,
        totalPages: pages,
        nextPage:   current < pages ? current + 1 : nil,
        softwares:  softwares.map { |sw| build_response(sw, sw.releases.to_a, counts, subject: subject) }
      }
    end

    # Returns the facet counts of the catalog as a Hash: +api+, the +total+
    # matching every filter, and +statuses+, +platforms+ and +categories+, each
    # counted with every filter but its own. Takes the filters of #index.
    def facets(owner_id: nil, subject: nil, statuses: [], platform: nil, category: nil, query: nil)
      base = filtered(visible_scope(subject), owner_id: owner_id, query: query)
      {
        api:        WarpEngine::API_VERSION,
        total:      filtered(base, statuses: statuses, platform: platform, category: category).count,
        statuses:   filtered(base, platform: platform, category: category).group(:status).count.transform_keys(&:to_s),
        platforms:  filtered(base, statuses: statuses, category: category).group(:platform).count,
        categories: filtered(base, statuses: statuses, platform: platform).group(:category).count.transform_keys(&:to_s)
      }
    end

    # Returns the vocabulary of the catalog as a Hash: +api+, the +statuses+
    # (+key+, +label+, +position+, +defaultVisible+, +badge+) and the
    # +categories+ (+key+, +label+, +position+ and the +count+ of softwares
    # visible to +subject+).
    def vocabulary(subject: nil)
      counts = visible_scope(subject).group(:category).count
      {
        api: WarpEngine::API_VERSION,
        statuses: WarpEngine::SoftwareStatus.ensured.map do |status|
          { key: status.key, label: status.label, position: status.position,
            defaultVisible: status.default_visible, badge: status.badge }
        end,
        categories: WarpEngine::SoftwareCategory.ordered.map do |category|
          { key: category.key, label: category.label, position: category.position,
            count: counts.fetch(category.key, 0) }
        end
      }
    end

    private

    def filtered(scope, owner_id: nil, statuses: [], platform: nil, category: nil, query: nil)
      scope.with_owner(owner_id).with_statuses(statuses).with_platform(platform).with_category(category).search(query)
    end

    def page_size(per_page, total, paged:)
      return [ total, 1 ].max unless paged || per_page.present?

      requested = per_page.present? ? per_page.to_i : WarpEngine.config.catalog_page_size.to_i
      requested.clamp(1, WarpEngine.config.catalog_max_page_size.to_i)
    end
  end
end
