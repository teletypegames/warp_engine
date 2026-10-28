module WarpEngine
  # Downloads a published file and records the download.
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
    error code: 403, desc: "The access policy refused this caller"
    error code: 404, desc: "File not found"
    # <tt>GET /api/download?path=...</tt>.
    #
    # [path] the file path, relative to the file container
    #
    # Locates the file through WarpEngine::DownloadService, which applies the
    # access policy and records a WarpEngine::Download. Sends the file as an
    # attachment, or redirects (302) to its storage URL when the storage adapter
    # is not local. Responds 400 for a blank path, 403 when the access policy
    # refuses the caller and 404 when there is no such file.
    def show
      path = params[:path]
      return render(json: { error: "Path is required" }, status: :bad_request) if path.blank?

      location = WarpEngine::DownloadService.new.locate(
        path: path,
        ip: request.remote_ip,
        user_agent: request.user_agent,
        referer: request.referer,
        subject: current_subject,
        request: request
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
