Rails.application.config.to_prepare do
  WarpEngine.configure do |c|
    # A build-artifactok és képek tárolási helye (defaultok az env-ből:
    # FILE_CONTAINER_PATH ill. IMAGE_CONTAINER_PATH).
    # c.file_container_path  = "/softwares"
    # c.image_container_path = "/images"

    # A /build/* endpointok shared secretje (default: ENV["UPDATE_SECRET"]).
    # Beállítatlan secret esetén az endpointok minden kérést elutasítanak.
    # c.update_secret = ENV["UPDATE_SECRET"]

    # A /build/* hitelesítési forrása — kizárólagos választás:
    #   :env      — a fenti shared secret érvényes (default)
    #   :database — csak DB-tárolt WarpEngine::ApplicationToken érvényes
    #               ("update" scope-pal); a shared secret ilyenkor NEM működik.
    # A :database módhoz kötelező a tokenek tulajdonos-osztálya is:
    # c.application_token_source = :database
    # c.application_token_owner_class = "AdminUser"

    # A /build/upload (és az admin file manager) méretplafonja bájtban (default: 500MB).
    # c.max_upload_size = 500 * 1024 * 1024

    # Owner-izoláció: DB-token csak a saját ownerének szoftvereit
    # uploadolhatja/publisholhatja (unrestricted token kivétel). Csak azután
    # kapcsold be, hogy a meglévő szoftverek ownert kaptak (backfill)!
    # c.enforce_software_ownership = true

    # Ha a host modelljei is hivatkoznak katalógus-képekre, regisztráld őket,
    # hogy az admin Images oldal orphan-detektálása figyelembe vegye:
    # c.image_owners = [
    #   {
    #     label: "member",
    #     image_ids: -> { Member.where.not(image_id: nil).distinct.pluck(:image_id) },
    #     usage_label: ->(image) { "member" if Member.where(image_id: image.id).exists? }
    #   }
    # ]
  end
end
