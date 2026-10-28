module WarpEngine
  # The software catalog.
  class Api::SoftwareController < ApiController
    resource_description do
      short "Software catalog"
    end

    def_param_group :external_link do
      property :ID, Integer, desc: "Link ID"
      property :softwareId, Integer, desc: "Parent software ID"
      property :label, String, desc: "Link label (e.g. GitHub)"
      property :url, String, desc: "Link URL"
    end

    def_param_group :software_image do
      property :url, String, desc: "Image URL (e.g. /api/image/123)"
      property :isDefault, :boolean, desc: "Default image flag"
      property :position, Integer, desc: "Display order"
    end

    def_param_group :release do
      property :ID, Integer, desc: "Release ID"
      property :softwareId, Integer, desc: "Parent software ID"
      property :version, String, desc: "Version string"
      property :cartridgePath, String, desc: "Cartridge file path"
      property :sourcePath, String, desc: "Source file path"
      property :htmlFolderPath, String, desc: "HTML playable folder path"
      property :docsFolderPath, String, desc: "Documentation folder path"
      property :downloadCount, Integer, desc: "Download count for this release"
    end

    api :GET, "/api/software", "The catalog: every visible software with its releases, whole or one page at a time"
    desc <<~DESC
      Without `page` the whole catalog comes back in one envelope, which is what every
      reader before API version 2 expects to find under `softwares`. With `page` the
      same envelope carries one page of `per_page` entries (default and ceiling are the
      host's `catalog_page_size` and `catalog_max_page_size`), and `nextPage` says
      whether there is another. Filters narrow the catalog before it is paged; the
      access policy decides visibility before either.
    DESC
    param :owner_id, :number, required: false, desc: "Filter to the softwares of one owner (publisher)"
    param :page, :number, required: false, desc: "Page number, from 1; absent means the whole catalog"
    param :per_page, :number, required: false, desc: "Entries per page, capped by the host"
    param :status, String, required: false, desc: "Comma-separated status keys (see /api/software/vocabulary)"
    param :platform, String, required: false, desc: "One platform name"
    param :category, String, required: false, desc: "One category key"
    param :q, String, required: false, desc: "Text matched against title and name"
    param :sort, %w[title updated newest], required: false, desc: "Order; title by default"
    returns code: 200, desc: "Envelope with the page and the softwares array" do
      property :api, Integer, desc: "Shape version of this JSON (WarpEngine::API_VERSION)"
      property :page, Integer, desc: "This page, from 1"
      property :perPage, Integer, desc: "Entries per page"
      property :total, Integer, desc: "Softwares matching the filters, all pages"
      property :totalPages, Integer, desc: "Pages at this size"
      property :nextPage, Integer, desc: "The next page, or null on the last"
      property :softwares, Array, desc: "Array of software entries" do
        property :ID, Integer, desc: "Software ID"
        property :name, String, desc: "Internal name"
        property :title, String, desc: "Display title"
        property :author, String, desc: "Author name"
        property :desc, String, desc: "Short description"
        property :story, String, desc: "Long description / story"
        property :license, String, desc: "License type"
        property :platform, String, desc: "Platform (one of WarpEngine::Platform.names)"
        property :status, String, desc: "Status (development, demo, released, archived)"
        property :highlighted, :boolean, desc: "Currently highlighted"
        property :imageUrl, String, desc: "Default image URL"
        property :externalLinks, Array, desc: "External links" do
          property :ID, Integer, desc: "Link ID"
          property :label, String, desc: "Link label"
          property :url, String, desc: "Link URL"
        end
        property :images, Array, desc: "Image gallery" do
          property :url, String, desc: "Image URL"
          property :isDefault, :boolean, desc: "Default image flag"
          property :position, Integer, desc: "Display order"
        end
      end
    end
    # <tt>GET /api/software</tt>.
    #
    # Renders the catalog envelope from WarpEngine::SoftwareService#index: the
    # softwares visible to the caller with their releases, filtered by
    # +owner_id+, +status+ (comma-separated keys), +platform+, +category+ and
    # +q+, ordered by +sort+. Without +page+ the whole catalog comes back; with
    # +page+ (and optional +per_page+) one page of it, with paging fields.
    def index
      render json: WarpEngine::SoftwareService.new.index(
        subject: current_subject, page: params[:page], per_page: params[:per_page], sort: params[:sort],
        **catalog_filters
      )
    end

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
