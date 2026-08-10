module WarpEngine
  class Configuration
    # Owner contract for image_owners elements:
    #   label:       String
    #   image_ids:   -> { Array<Integer> }        — image ids used by the owner
    #   usage_label: ->(image) { String or nil }  — label to display when in use
    # application_token_source: auth source of the /build/* endpoints, exclusive.
    #   :env      — the shared secret (update_secret) is accepted, DB tokens are not
    #   :database — only WarpEngine::ApplicationToken is accepted, the shared secret is not
    # application_token_owner_class: class name of the mandatory token owner
    # (e.g. "AdminUser"); nil makes :database mode reject every request.
    # storage_adapter: where build artifacts are served from.
    #   :local (default) — the local filesystem under file_container_path,
    #                      byte for byte the previous behaviour;
    #   any object       — must answer file?/directory?/locate, see
    #                      WarpEngine::Storage. Serving only: uploads and
    #                      archive extraction still write to the local disk.
    # max_upload_size: file size cap in bytes for /build/upload (and the admin file manager).
    # enforce_software_ownership: when true, a DB token may only upload/publish
    # its own owner's softwares (unrestricted tokens are exempt).
    # Enable ONLY after the backfill: any token can claim an ownerless software.
    # ci_platforms: platforms served by /build/config:
    #   { "godot" => { builder: "<image>" }, "tic80" => { builder: ..., exporter: ... } }
    #   Empty map = the feature is inactive (POST → 204, GET → 404).
    # ci_extension_public_key(_url): the Woodpecker httpsig ed25519 public key as
    #   PEM, or a URL to fetch it from (e.g. https://ci.../api/signature/public-key).
    #   With neither set, POST /build/config rejects every request.
    # ci_update_server: server URL written into the upload/publish steps; nil → the request's base_url.
    # woodpecker_url / woodpecker_api_token / woodpecker_repo_owner:
    #   Woodpecker CI management (repo sync, secret provisioning, pipeline control).
    #   All nil → the management features are inactive.
    attr_accessor :file_container_path,
                  :image_container_path,
                  :update_secret,
                  :application_token_source,
                  :application_token_owner_class,
                  :max_upload_size,
                  :enforce_software_ownership,
                  :ci_platforms,
                  :ci_extension_public_key,
                  :ci_extension_public_key_url,
                  :ci_update_server,
                  :woodpecker_url,
                  :woodpecker_api_token,
                  :woodpecker_repo_owner,
                  :image_owners,
                  :storage_adapter

    def initialize
      @file_container_path           = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
      @image_container_path          = ENV.fetch("IMAGE_CONTAINER_PATH", "/images")
      @update_secret                 = ENV["UPDATE_SECRET"]
      @application_token_source      = :env
      @application_token_owner_class = nil
      @max_upload_size               = 500 * 1024 * 1024
      @enforce_software_ownership    = false
      @ci_platforms                  = {}
      @ci_extension_public_key       = nil
      @ci_extension_public_key_url   = nil
      @ci_update_server              = nil
      @woodpecker_url                = ENV["WOODPECKER_URL"]
      @woodpecker_api_token          = ENV["WOODPECKER_API_TOKEN"]
      @woodpecker_repo_owner         = ENV["WOODPECKER_REPO_OWNER"]
      @image_owners                  = []
      @storage_adapter               = :local
    end
  end
end
