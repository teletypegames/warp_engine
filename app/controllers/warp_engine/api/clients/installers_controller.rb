module WarpEngine
  module Api
    module Clients
      # The installer of a store engine (WarpEngine::Clients) for this
      # catalog: a shell script a machine pipes into its shell.
      class InstallersController < ApiController
        include WarpEngine::ClientConfigUrls

        resource_description do
          short "Store engines"
        end

        api :GET, "/api/stores/:client/install.sh", "The installer of a store engine for this catalog"
        param :client, String, required: true, desc: "batocera or retroarch"
        desc <<~DESC
          A shell script: `curl -fsSL …/api/stores/batocera/install.sh | sh` on the machine downloads the
          engine release this catalog runs and installs it with this catalog's store config. Public on
          purpose: the machine has nobody to log in as.
        DESC
        error code: 404, desc: "Not a store engine, or the catalog has no release of it"
        # <tt>GET /api/stores/:client/install.sh</tt>.
        #
        # Renders WarpEngine::ClientConfigService#installer as
        # <tt>text/x-shellscript</tt>; 404 when +client+ is not a store engine
        # or its software has no release to run.
        def show
          archive = "#{catalog_url}#{download_path(client_configs.release(client: params[:client]).path)}"
          render plain: client_configs.installer(client: params[:client], base_url: catalog_url,
                                                install_url: client_config_url("install.sh"),
                                                config_url: client_config_url("config.json"), archive_url: archive),
                 content_type: "text/x-shellscript"
        end
      end
    end
  end
end
