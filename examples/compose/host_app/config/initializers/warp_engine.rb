Rails.application.config.to_prepare do
  WarpEngine.configure do
    file_container_path ENV.fetch("FILE_CONTAINER_PATH", "/softwares")

    update_secret ENV["UPDATE_SECRET"]

    image_class "Image"

    ci :woodpecker do
      url        ENV["WOODPECKER_URL"]
      api_token  ENV["WOODPECKER_API_TOKEN"]
      repo_owner ENV["WOODPECKER_REPO_OWNER"]
    end
  end
end
