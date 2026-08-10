module WarpEngine
  class Api::DownloadsController < ApiController
    resource_description do
      short "File downloads"
      formats [ "binary" ]
    end

    api :GET, "/api/download", "Download a file by path"
    param :path, String, required: true, desc: "File path to download"
    returns code: 200, desc: "File binary data"
    returns code: 302, desc: "Redirect to the storage location (non-local storage adapter)"
    error code: 400, desc: "Path is blank"
    error code: 404, desc: "File not found"
    def show
      path = params[:path]
      return render(json: { error: "Path is required" }, status: :bad_request) if path.blank?

      location = WarpEngine::DownloadService.new.locate(
        path: path,
        ip: request.remote_ip,
        user_agent: request.user_agent,
        referer: request.referer
      )

      if location.nil?
        render json: { error: "Not found" }, status: :not_found
      elsif location.redirect?
        redirect_to location.url, allow_other_host: true
      else
        send_file location.path, disposition: "attachment", type: resolve_mime(location.path)
      end
    end
  end
end
