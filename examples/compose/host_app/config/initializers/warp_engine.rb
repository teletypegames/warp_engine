Rails.application.config.to_prepare do
  WarpEngine.configure do |c|
    c.file_container_path  = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
    c.image_container_path = ENV.fetch("IMAGE_CONTAINER_PATH", "/images")

    c.update_secret = ENV["UPDATE_SECRET"]
  end
end
