module WarpEngine
  module Api
    # The store registry a graphical client reads on its first run
    # (WarpEngine::StoreRegistry).
    class StoresController < ApiController
      resource_description do
        short "Store registry"
      end

      api :GET, "/api/stores", "List the stores a client can install from"
      desc <<~DESC
        The registry the WarpEngine Client reads on its first run: which catalogs it can
        install. Public on purpose: a client has nobody to log in as.

        A name and a catalog URL are the whole record. How a store behaves is fixed per
        installed client, so the registry says what a store *is* and nothing about how it
        works. By default the list is this catalog alone; the host can list others too,
        or turn the registry off, in which case this answers 404.
      DESC
      returns code: 200, desc: "Array of stores" do
        property :name, String, desc: "Display name of the store"
        property :catalogUrl, String, desc: "Base URL of the WarpEngine catalog it serves"
      end
      error code: 404, desc: "The host turned the registry off"
      # <tt>GET /api/stores</tt>.
      #
      # Renders WarpEngine::StoreRegistry.stores for this deployment's address
      # as a JSON array of <tt>{ name, catalogUrl }</tt>; 404 with no body when
      # the registry is off. Needs no credential.
      def index
        return head :not_found unless StoreRegistry.enabled?

        render json: StoreRegistry.stores(catalog_url: "#{request.base_url}#{request.script_name}")
      end
    end
  end
end
