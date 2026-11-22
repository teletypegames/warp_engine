module WarpEngine
  module Api
    # The endpoints of the store engines this catalog serves (WarpEngine::StoreClients),
    # under <tt>/api/stores/:client/</tt>.
    module StoreClients
      # The store config of a store engine (WarpEngine::StoreClients) for
      # this catalog: the config.json the installer sets the store up with.
      class ConfigsController < ApiController
        include WarpEngine::StoreClientUrls

        resource_description do
          short "Store engines"
        end

        api :GET, "/api/stores/:client/config.json", "The store config of a store engine for this catalog"
        param :client, String, required: true, desc: "batocera or retroarch"
        desc "This catalog, the store's name and id, what it installs and where, and where the engine asks " \
             "which release to run. Public on purpose: the installer reads it before anybody could sign in."
        error code: 404, desc: "Not a store engine"
        # <tt>GET /api/stores/:client/config.json</tt>.
        #
        # Renders WarpEngine::StoreClientService#config as JSON; 404 when
        # +client+ is not a store engine.
        def show
          render json: store_clients.config(client: params[:client], base_url: catalog_url, release_path: release_path)
        end
      end
    end
  end
end
