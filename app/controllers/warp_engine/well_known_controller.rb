module WarpEngine
  # Tells a developer tool what answers at this address before it signs in:
  # <tt>GET /.well-known/warp-engine</tt>, public. An editor extension probing
  # a port on its own machine learns from it that a WarpEngine runs there,
  # whether it is a local engine (WarpEngine::Configuration#profile) and how to
  # sign in to it; a remote engine tells whether it takes syncs and how a peer
  # pairs with it.
  class WellKnownController < ApiController
    resource_description do
      short "What this engine is, for developer tools"
    end

    # How a tool signs in, by profile.
    SIGN_IN = { server: %w[tool-sign-in], local: %w[token-file] }.freeze

    api :GET, "/.well-known/warp-engine", "What this engine is"
    returns code: 200, desc: %(JSON: {"engine": "warp-engine", "version": ..., "profile": "server" | "local", ...})
    # <tt>GET /.well-known/warp-engine</tt>.
    #
    # Renders the engine, its version and catalog API version, its name, its
    # profile and sign-in, where the Admin API is (+nil+ when it is off),
    # whether an admin web UI is loaded, and the sync settings a tool needs:
    # whether this engine takes syncs (+inbound+) and the engine it means to
    # sync to (+target+).
    def show
      render json: {
        engine:   "warp-engine",
        version:  WarpEngine::VERSION,
        api:      WarpEngine::API_VERSION,
        name:     name,
        profile:  engine_config.profile.to_s,
        signIn:   SIGN_IN.fetch(engine_config.profile),
        adminApi: (WarpEngine::AdminApi.url_path if WarpEngine::AdminApi.config.enabled?),
        admin:    defined?(::ActiveAdmin) ? true : false,
        sync:     { inbound: WarpEngine::Sync.config.inbound.enabled?, target: engine_config.sync_target.presence }
      }
    end

    private

    def engine_config = WarpEngine.config

    def name
      engine_config.store_name.to_s.strip.presence || request.host
    end
  end
end
