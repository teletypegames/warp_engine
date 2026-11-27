module WarpEngine
  module Feeds
    # The endpoints of the Assembly64 feed (WarpEngine::Feeds::Assembly64),
    # under <tt>/leet/search</tt>. The routes only match when a configured
    # feed answers the request's host; the feed found decides everything
    # else, its Assembly64::Catalog answers. Answers like Assembly64 does: JSON without an envelope, an empty
    # list for a search that fails, CORS open, and a file as
    # <tt>application/octet-stream</tt> with a +Content-Disposition+ name. A
    # <tt>Client-Id</tt> the feed does not accept gets 403
    # <tt>{ "errorCode": 464 }</tt>, the code Assembly64 answers it with.
    class Assembly64Controller < ActionController::API
      include WarpEngine::VersionHeader

      before_action :set_cors_headers
      before_action :check_client

      # <tt>GET /leet/search/aql/presets</tt>: the presets of the search form
      # (WarpEngine::Feeds::Assembly64::Catalog#presets) as a JSON array.
      def presets
        render json: catalog.presets
      end

      # <tt>GET /leet/search/categories</tt>: the categories behind the
      # +category+ ids of the results
      # (WarpEngine::Feeds::Assembly64::Catalog#categories) as a JSON array.
      # The <tt>Assembly64/1.0</tt> firmware asks for it after a search and
      # keeps asking while it is missing.
      def categories
        render json: catalog.categories
      end

      # <tt>GET /leet/search/aql?query=</tt> and
      # <tt>GET /leet/search/aql/:start/:count?query=</tt>: the search
      # results (WarpEngine::Feeds::Assembly64::Catalog#search) as a JSON array; an
      # empty one when the search fails (the error is logged).
      def search
        render json: catalog.search(params[:query], start: params[:start], count: params[:count])
      rescue StandardError => e
        Rails.logger.error("[WarpEngine::Feeds::Assembly64] search: #{e.class}: #{e.message}")
        render json: []
      end

      # <tt>GET /leet/search/screenshot/:id/:category</tt>: the default image
      # of a title (WarpEngine::Feeds::Assembly64::Catalog#screenshot) as an
      # attachment, as the reference server sends it; a redirect when the
      # image adapter only gives an absolute URL; 404 with an empty body when
      # the title is not in the selection or has no image.
      def screenshot
        image = catalog.screenshot(params[:id])
        if image&.dig(:path)
          send_file image[:path], disposition: "attachment", type: "application/octet-stream",
                                  filename: "screenshot#{File.extname(image[:path]).downcase}"
        elsif image&.dig(:url).to_s.match?(%r{\Ahttps?://})
          redirect_to image[:url], allow_other_host: true
        else
          head :not_found
        end
      end

      # <tt>GET /leet/search/metadata/:id/:category</tt> (and +meta+): the details of a
      # title (WarpEngine::Feeds::Assembly64::Catalog#metadata); 404 with an
      # empty body when it is not in the selection.
      def metadata
        result = catalog.metadata(params[:id])
        result ? render(json: result) : head(:not_found)
      end

      # <tt>GET /leet/search/entries/:id/:category</tt>: the files of a title
      # (WarpEngine::Feeds::Assembly64::Catalog#entries); 404 with an empty body when
      # it is not in the selection.
      def entries
        result = catalog.entries(params[:id])
        result ? render(json: result) : head(:not_found)
      end

      # <tt>GET /leet/search/bin/:id/:category/:file</tt>: one file of a
      # title, through WarpEngine::DownloadService (access check and download
      # log, with the request's <tt>Client-Id</tt> and the feed's key). Sends it as an attachment, redirects to it when the storage
      # serves it elsewhere, or answers 404 with an empty body when there is
      # no such file; 403 with an empty body when the access policy refuses.
      def bin
        item = catalog.item(params[:id], params[:file])
        return head(:not_found) if item.nil?

        location = WarpEngine::DownloadService.new.locate(
          path: item.relative_path, ip: request.remote_ip, user_agent: request.user_agent,
          referer: request.referer, request: request,
          client_id: request.headers["Client-Id"], feed: feed.key
        )
        if location.nil?
          head :not_found
        elsif location.redirect?
          redirect_to location.url, allow_other_host: true
        else
          send_file location.path, disposition: "attachment", filename: catalog.file_name(item), type: "application/octet-stream"
        end
      rescue WarpEngine::AccessDenied
        head :forbidden
      end

      private

      def feed
        @feed ||= WarpEngine::Feeds.serving(WarpEngine::Feeds::Assembly64.type_name, request)
      end

      def catalog = @catalog ||= feed.catalog

      def set_cors_headers
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "token,client-id,Content-Type,Range"
      end

      def check_client
        return head(:not_found) if feed.nil?
        return if feed.client_allowed?(request.headers["Client-Id"])

        render json: { errorCode: 464, errorMessage: "Unknown client" }, status: :forbidden
      end
    end
  end
end
