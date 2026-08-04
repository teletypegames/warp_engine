module WarpEngine
  class Api::ImagesController < ApiController
    resource_description do
      short "Images"
      formats [ "binary" ]
    end

    api :GET, "/api/image/:id", "Get image by ID"
    param :id, :number, required: true, desc: "Image ID"
    returns code: 200, desc: "Image binary data"
    error code: 404, desc: "Image not found"
    def show
      image = WarpEngine::ImageService.new.show(WarpEngine::ImageShowInputDto.new(id: params[:id]))
      send_file image.file_path, type: image.content_type, disposition: "inline"
    end
  end
end
