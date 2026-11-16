module WarpEngine
  # Controller concern that reads the catalog filters <tt>GET /api/software</tt>
  # and <tt>GET /api/software/facets</tt> share from the request parameters.
  module CatalogFilters
    extend ActiveSupport::Concern

    private

    def catalog_filters
      {
        owner_id: params[:owner_id],
        statuses: params[:status].to_s.split(",").map(&:strip).reject(&:blank?),
        platform: params[:platform].presence,
        category: params[:category].presence,
        query:    params[:q].presence
      }
    end
  end
end
