module WarpEngine
  class Api::DownloadsController < ApiController
    resource_description do
      short "File downloads"
      formats [ "binary" ]
    end

    api :GET, "/api/download", "Download a file by path"
    param :path, String, required: true, desc: "File path to download"
    returns code: 200, desc: "File binary data"
    error code: 400, desc: "Path is blank"
    error code: 404, desc: "File not found"
    def show
      path = params[:path]
      return render(json: { error: "Path is required" }, status: :bad_request) if path.blank?

      full_path = WarpEngine::DownloadService.new.create(
        path: path,
        ip: request.remote_ip,
        user_agent: request.user_agent,
        referer: request.referer
      )

      if full_path
        send_file full_path, disposition: "attachment", type: resolve_mime(full_path)
      else
        render json: { error: "Not found" }, status: :not_found
      end
    end
  end
end
