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

    # Size cap in bytes for /build/upload (and the admin file manager, default: 500MB).
    # c.max_upload_size = 500 * 1024 * 1024

    # Owner isolation: a DB token may only upload/publish its own owner's
    # softwares (unrestricted tokens are exempt). Enable only after existing
    # softwares got an owner (backfill)!
    # c.enforce_software_ownership = true

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
