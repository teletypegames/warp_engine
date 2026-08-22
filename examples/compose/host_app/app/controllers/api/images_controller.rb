module Api
  class ImagesController < ActionController::API
    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "Not found" }, status: :not_found
    end

    rescue_from Errno::ENOENT do
      render json: { error: "Not found" }, status: :not_found
    end

    def show
      image = Image.find(params[:id])
      send_file image.file_path, type: image.content_type, disposition: "inline"
    end
  end
end
