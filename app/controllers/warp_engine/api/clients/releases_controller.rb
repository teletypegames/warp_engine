module WarpEngine
  module Api
    module Clients
      # The engine release the machines of a store engine
      # (WarpEngine::Clients) run, which an installed engine checks to
      # update itself.
      class ReleasesController < ApiController
        include WarpEngine::ClientConfigUrls

        resource_description do
          short "Store engines"
        end

        api :GET, "/api/stores/:client/release", "The engine release the machines of a store run"
        param :client, String, required: true, desc: "batocera or retroarch"
        desc "What an installed engine checks on every sync: when the version differs from its own it " \
             "downloads the archive at `url`, checks its `size` and runs that instead. Public on purpose: " \
             "the machine has nobody to log in as."
        returns code: 200, desc: "The release" do
          property :software, String, desc: "The catalog software of the engine"
          property :version, String, desc: "The version to run"
          property :url, String, desc: "Where the archive is downloaded from, relative to the catalog"
          property :size, Integer, desc: "The archive's size in bytes, or null"
        end
        error code: 404, desc: "Not a store engine, or the catalog has no release of it"
        # <tt>GET /api/stores/:client/release</tt>.
        #
        # Renders WarpEngine::ClientConfigService#release as
        # <tt>{ software, version, url, size }</tt>; 404 when +client+ is not
        # a store engine or its software has no release to run.
        def show
          target = client_configs.release(client: params[:client])
          render json: { software: target.software, version: target.version, url: download_path(target.path),
                         size: target.size }
        end
      end
    end
  end
end
