Rails.application.config.to_prepare do
  WarpEngine.configure do |c|
    # Storage locations for build artifacts and images (defaults from ENV:
    # FILE_CONTAINER_PATH and IMAGE_CONTAINER_PATH).
    # c.file_container_path  = "/softwares"
    # c.image_container_path = "/images"

    # Shared secret of the /build/* endpoints (default: ENV["UPDATE_SECRET"]).
    # With no secret configured the endpoints reject every request.
    # c.update_secret = ENV["UPDATE_SECRET"]

    # Auth source of the /build/* endpoints — an exclusive choice:
    #   :env      — the shared secret above is accepted (default)
    #   :database — only DB-stored WarpEngine::ApplicationToken records are
    #               accepted (with the "update" scope); the shared secret
    #               stops working the moment you switch.
    # :database mode also requires the owner class every token belongs to:
    # c.application_token_source = :database
    # c.application_token_owner_class = "AdminUser"

    # Woodpecker configuration extension (/build/config): builder images of
    # the served platforms and the CI server's signing key. An empty
    # ci_platforms (default) keeps the feature inactive.
    # c.ci_platforms = {
    #   "godot" => { builder: "registry.example/godot-builder:4.6" },
    #   "tic80" => { builder: "registry.example/tic80-builder:1.0",
    #                exporter: "registry.example/tic80pro:1.0" }
    # }
    # c.ci_extension_public_key_url = "https://ci.example.org/api/signature/public-key"
    # c.ci_update_server = nil # nil: the request base_url

    # Woodpecker CI management — repo sync, secret provisioning, pipeline control.
    # All three must be set for the management features to activate.
    # c.woodpecker_url        = ENV["WOODPECKER_URL"]        # e.g. "https://ci.example.org"
    # c.woodpecker_api_token  = ENV["WOODPECKER_API_TOKEN"]  # Woodpecker PAT with admin access
    # c.woodpecker_repo_owner = ENV["WOODPECKER_REPO_OWNER"] # forge org/user (e.g. "games")

    # Size cap in bytes for /build/upload (and the admin file manager, default: 500MB).
    # c.max_upload_size = 500 * 1024 * 1024

    # Owner isolation: a DB token may only upload/publish its own owner's
    # softwares (unrestricted tokens are exempt). Enable only after existing
    # softwares got an owner (backfill)!
    # c.enforce_software_ownership = true

    # Who may see a title and who may download it. :open (the default) lists every
    # software and serves every artifact — the behaviour of a catalog nobody sells
    # from. A host that does sell supplies a policy answering three methods; see
    # WarpEngine::AccessPolicy. What it returns is what clients are told, so a paid
    # title can announce itself as paid instead of failing at the download.
    # c.access_policy = MyStore::AccessPolicy.new

    # Client sign-in. nil (default) means there is none: /api/auth/* is inactive and
    # GET /api/service reports auth: null, so a client offers no sign-in at all. Set
    # the class a *client* token belongs to — usually your user model — to turn on
    # the device authorization grant.
    # c.access_token_owner_class = "User"
    #
    # Your own page where a signed-in person types the code their client displayed.
    # It calls WarpEngine::DeviceGrantService#approve. A path is made absolute
    # against the request, so you need not know your own hostname (default "/devices").
    # c.identity_verification_url = "/devices"
    # c.device_code_ttl      = 600  # seconds a pending code lives
    # c.device_code_interval = 5    # seconds a client is told to wait between polls

    # If host models also reference catalog images, register them so the
    # admin Images page's orphan detection takes them into account:
    # c.image_owners = [
    #   {
    #     label: "member",
    #     image_ids: -> { Member.where.not(image_id: nil).distinct.pluck(:image_id) },
    #     usage_label: ->(image) { "member" if Member.where(image_id: image.id).exists? }
    #   }
    # ]
  end
end
