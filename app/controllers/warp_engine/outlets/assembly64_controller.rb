module WarpEngine
  module Outlets
    # The endpoints of the Assembly64 outlet (WarpEngine::Outlets::Assembly64),
    # under <tt>/leet/search</tt>. The routes only match when a configured
    # outlet answers the request's host; the outlet found decides everything
    # else. Answers like Assembly64 does: JSON without an envelope, an empty
    # list for a search that fails, CORS open, and a file as
    # <tt>application/octet-stream</tt> with a +Content-Disposition+ name. A
    # <tt>Client-Id</tt> the outlet does not accept gets 403
    # <tt>{ "errorCode": 464 }</tt>, the code Assembly64 answers it with.
    class Assembly64Controller < ActionController::API
      before_action :set_headers
      before_action :check_client

      # <tt>GET /leet/search/aql/presets</tt>: the presets of the search form
      # (WarpEngine::Outlets::Assembly64#presets) as a JSON array.
      def presets
        render json: outlet.presets
      end

      # <tt>GET /leet/search/aql?query=</tt> and
      # <tt>GET /leet/search/aql/:start/:count?query=</tt>: the search
      # results (WarpEngine::Outlets::Assembly64#search) as a JSON array; an
      # empty one when the search fails (the error is logged).
      def search
        render json: outlet.search(params[:query], start: params[:start], count: params[:count])
      rescue StandardError => e
        Rails.logger.error("[WarpEngine::Outlets::Assembly64] search: #{e.class}: #{e.message}")
        render json: []
      end

      # <tt>GET /leet/search/entries/:id/:category</tt>: the files of a title
      # (WarpEngine::Outlets::Assembly64#entries); 404 with an empty body when
      # it is not on offer.
      def entries
        result = outlet.entries(params[:id])
        result ? render(json: result) : head(:not_found)
      end

      # <tt>GET /leet/search/bin/:id/:category/:file</tt>: one file of a
      # title, through WarpEngine::DownloadService (access check and download
      # log). Sends it as an attachment, redirects to it when the storage
      # serves it elsewhere, or answers 404 with an empty body when there is
      # no such file; 403 with an empty body when the access policy refuses.
      def bin
        item = outlet.item(params[:id], params[:file])
        return head(:not_found) if item.nil?

        location = WarpEngine::DownloadService.new.locate(
          path: item.relative_path, ip: request.remote_ip, user_agent: request.user_agent,
          referer: request.referer, request: request
        )
        if location.nil?
          head :not_found
        elsif location.redirect?
          redirect_to location.url, allow_other_host: true
        else
          send_file location.path, disposition: "attachment", filename: outlet.file_name(item), type: "application/octet-stream"
        end
      rescue WarpEngine::AccessDenied
        head :forbidden
      end

      private

      def outlet
        @outlet ||= WarpEngine::Outlets.serving(WarpEngine::Outlets::Assembly64.type_name, request)
      end

      def set_headers
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "token,client-id,Content-Type,Range"
        response.headers["WarpEngine-Version"] = WarpEngine::VERSION
      end

      def check_client
        return head(:not_found) if outlet.nil?
        return if outlet.client_allowed?(request.headers["Client-Id"])

        render json: { errorCode: 464, errorMessage: "Unknown client" }, status: :forbidden
      end
    end
  end
end
