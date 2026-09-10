module WarpEngine
  class Api::ServiceController < ApiController
    resource_description do
      short "Service descriptor"
    end

    api :GET, "/api/service", "What this WarpEngine deployment offers"
    desc <<~DESC
      Public on purpose: a client reads this *before* it can have a credential.

      `auth` is null where the host has configured no client identity — the catalog is
      open, there is nobody to sign in as, and a client should not offer to. Where it is
      present, `auth.device` describes the device authorization grant a client with no
      browser of its own uses to sign in.

      `catalog.gated` says whether any title here can require an entitlement. A client
      can render a store that never gates differently from one that sometimes does,
      without having to read the whole catalog first to find out.
    DESC
    returns code: 200, desc: "The descriptor" do
      property :engine, String, desc: "Always 'warp_engine'"
      property :version, String, desc: "Engine version, same value as the WarpEngine-Version header"
      property :api, Hash, desc: "The JSON shape and the catalog's paging" do
        property :version, Integer, desc: "Shape version every catalog envelope also carries"
        property :catalog, Hash, desc: "Paging" do
          property :pageSize, Integer, desc: "Entries per page when a client asks for a page without saying how many"
          property :maxPageSize, Integer, desc: "The most a client may ask for"
        end
      end
      property :catalog, Hash, desc: "Catalog properties" do
        property :gated, :boolean, desc: "Whether titles here can require an entitlement"
      end
      property :auth, Hash, desc: "How to sign in, or null where there is no sign-in"
    end
    def show
      render json: {
        engine:  "warp_engine",
        version: WarpEngine::VERSION,
        api: {
          version: WarpEngine::API_VERSION,
          catalog: {
            pageSize:    WarpEngine.config.catalog_page_size.to_i,
            maxPageSize: WarpEngine.config.catalog_max_page_size.to_i
          }
        },
        catalog: { gated: !WarpEngine::AccessPolicy.open? },
        auth:    auth_descriptor
      }
    end

    private

    def auth_descriptor
      return nil unless WarpEngine.identity_configured?

      service = WarpEngine::DeviceGrantService.new
      {
        schemes: [ "bearer" ],
        device: {
          authorizeUrl:    warp_engine.api_auth_device_url,
          tokenUrl:        warp_engine.api_auth_device_token_url,
          revokeUrl:       warp_engine.api_auth_token_url,
          verificationUrl: service.verification_url(base_url: request.base_url),
          interval:        WarpEngine.config.device_code_interval.to_i
        }
      }
    end
  end
end
