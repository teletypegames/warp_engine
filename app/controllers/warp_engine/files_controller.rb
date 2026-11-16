module WarpEngine
  # Serves published files under <tt>/file</tt>.
  class FilesController < ApiController
    resource_description do
      short "Static files"
      formats [ "binary" ]
    end

    api :GET, "/file/*path", "Serve or redirect to a file"
    param :path, String, required: true, desc: "File path"
    returns code: 200, desc: "File binary data"
    returns code: 301, desc: "Redirect to file URL"
    error code: 403, desc: "The access policy refused this caller"
    error code: 404, desc: "File not found"
    # <tt>GET /file/*path</tt>.
    #
    # Resolves the path through WarpEngine::FileService, which applies the
    # access policy. Sends the file inline; redirects (301) a folder to its
    # <tt>index.html</tt> (under the engine's mount) and a file of a non-local storage adapter to its
    # storage URL; responds 404 when there is no such file or folder index.
    # A refused caller gets 403. A runtime's file (under <tt>_runtimes/</tt>)
    # is sent as public and immutable for a year: its version is in the URL
    # and its files never change.
    def show
      result = WarpEngine::FileService.new.show(path: params[:path], subject: current_subject)
      case result.type
      when :index     then redirect_to file_path(path: result.path), status: :moved_permanently
      when :redirect  then redirect_to result.url, status: :moved_permanently
      when :file
        expires_in 1.year, public: true, immutable: true if params[:path].to_s.start_with?("#{WarpEngine::Runtime::ROOT}/")
        send_file result.path, disposition: "inline", type: resolve_mime(result.path)
      when :not_found then head :not_found
      end
    end
  end
end
