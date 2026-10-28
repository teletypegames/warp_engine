module WarpEngine
  # The public service descriptor a client reads before anything else.
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

      `admin` is null unless the host turned the Admin API on. Where present it names the
      Admin API's version and addresses; what lives there needs an admin token.

      `shelves` lists the shelves the host keeps: the latest build of every listed title of
      a platform, in a folder a machine without HTTPS can read, and where that folder is
      served (`urls`, as the host configured them; empty when it named none).
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
      property :admin, Hash, desc: "The Admin API, or null where it is off" do
        property :version, Integer, desc: "Admin API version (WarpEngine::AdminApi::VERSION)"
        property :url, String, desc: "Base address of the Admin API"
        property :openapiUrl, String, desc: "Its OpenAPI 3.1 document"
        property :mcpUrl, String, desc: "Its MCP endpoint, or null where MCP is off"
        property :schemes, Array, desc: "Authorization schemes; always bearer"
      end
      property :shelves, Array, desc: "The shelves of this deployment" do
        property :platform, String, desc: "The platform whose titles are on it"
        property :kinds, Array, desc: "The asset kinds it holds"
        property :layout, String, desc: "flat (one file a title) or folders (one folder a title, with INFO.INI and FILES.LST)"
        property :index, String, desc: "The index file in its folder"
        property :urls, Array, desc: "Where the folder is served"
      end
    end
    # <tt>GET /api/service</tt>.
    #
    # Renders what this deployment offers: the engine name and version, the API
    # shape version and catalog paging limits, whether the catalog is gated, the
    # device sign-in endpoints (+auth+, +null+ without client identity), the
    # Admin API addresses (+admin+, +null+ while it is off) and the shelf
    # descriptors. Needs no credential.
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
        auth:    auth_descriptor,
        admin:   admin_descriptor,
        shelves: WarpEngine::Shelves.descriptors
      }
    end

    private

    def admin_descriptor
      config = WarpEngine.config.admin_api
      return nil unless config.enabled?

      {
        version:    WarpEngine::AdminApi::VERSION,
        url:        "#{request.base_url}#{request.script_name}#{WarpEngine::AdminApi.url_path}",
        openapiUrl: warp_engine.api_admin_openapi_url,
        mcpUrl:     config.mcp? ? warp_engine.api_admin_mcp_url : nil,
        schemes:    [ "bearer" ]
      }
    end

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
