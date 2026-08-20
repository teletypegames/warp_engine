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
      property :catalog, Hash, desc: "Catalog properties" do
        property :gated, :boolean, desc: "Whether titles here can require an entitlement"
      end
      property :auth, Hash, desc: "How to sign in, or null where there is no sign-in"
    end
    def show
      render json: {
        engine:  "warp_engine",
        version: WarpEngine::VERSION,
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
