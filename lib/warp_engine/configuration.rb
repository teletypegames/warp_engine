module WarpEngine
  class Configuration
    # Owner kontraktus az image_owners elemeire:
    #   label:       String
    #   image_ids:   -> { Array<Integer> }         — az owner által használt image id-k
    #   usage_label: ->(image) { String vagy nil } — megjelenítendő címke, ha használja
    # application_token_source: a /build/* endpointok hitelesítési forrása, kizárólagos.
    #   :env      — a shared secret (update_secret) érvényes, a DB-tokenek nem
    #   :database — csak WarpEngine::ApplicationToken érvényes, a shared secret nem
    # application_token_owner_class: a tokenek kötelező tulajdonosának osztályneve
    # (pl. "AdminUser"); nil esetén a :database mód minden kérést elutasít.
    # max_upload_size: a /build/upload (és az admin file manager) fájlméret-plafonja bájtban.
    # enforce_software_ownership: ha true, egy DB-token csak a saját ownerének
    # szoftvereit uploadolhatja/publisholhatja (unrestricted token kivétel).
    # Bekapcsolás CSAK backfill után: gazdátlan software-t bármely token elvihet.
    # ci_platforms: a /build/config által kiszolgált platformok:
    #   { "godot" => { builder: "<image>" }, "tic80" => { builder: ..., exporter: ... } }
    #   Üres map = a feature inaktív (POST → 204, GET → 404).
    # ci_extension_public_key(_url): a Woodpecker httpsig ed25519 publikus kulcsa
    #   PEM-ben, vagy URL, ahonnan letölthető (pl. https://ci.../api/signature/public-key).
    #   Egyik sincs beállítva → a POST /build/config minden kérést elutasít.
    # ci_update_server: az upload/publish stepekbe írt szerver-URL; nil → a kérés base_url-je.
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
                  :image_owners

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
      @image_owners                  = []
    end
  end
end
