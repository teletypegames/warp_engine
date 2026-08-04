module WarpEngine
  class FilesController < ApiController
    resource_description do
      short "Static files"
      formats [ "binary" ]
    end

    api :GET, "/file/*path", "Serve or redirect to a file"
    param :path, String, required: true, desc: "File path"
    returns code: 200, desc: "File binary data"
    returns code: 301, desc: "Redirect to file URL"
    error code: 404, desc: "File not found"
    def show
      result = WarpEngine::FileService.new.show(WarpEngine::FileShowInputDto.new(path: params[:path]))
      case result.type
      when :redirect  then redirect_to result.url, status: :moved_permanently
      when :file      then send_file result.path, disposition: "inline", type: resolve_mime(result.path)
      when :not_found then head :not_found
      end
    end
  end
end
