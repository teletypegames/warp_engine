Rails.application.config.to_prepare do
  WarpEngine.configure do |c|
    # A build-artifactok és képek tárolási helye (defaultok az env-ből:
    # FILE_CONTAINER_PATH ill. IMAGE_CONTAINER_PATH).
    # c.file_container_path  = "/softwares"
    # c.image_container_path = "/images"

    # A /update endpoint shared secretje (default: ENV["UPDATE_SECRET"]).
    # Beállítatlan secret esetén az endpoint minden kérést elutasít.
    # c.update_secret = ENV["UPDATE_SECRET"]

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
