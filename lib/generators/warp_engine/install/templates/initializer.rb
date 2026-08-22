Rails.application.config.to_prepare do
  WarpEngine.configure do |c|
    c.file_container_path = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")

    c.update_secret = ENV["UPDATE_SECRET"]

    c.image_class_name = "Image"

    c.ci_adapter = WarpEngine::CI::Woodpecker::Adapter.new(
      url:            ENV["WOODPECKER_URL"],
      api_token:      ENV["WOODPECKER_API_TOKEN"],
      repo_owner:     ENV["WOODPECKER_REPO_OWNER"],
      public_key_url: ENV["WOODPECKER_PUBLIC_KEY_URL"],
      platforms:      {}
    )
  end
end
