module WarpEngine
  module Api
    module Admin
      # The Admin API's MCP (Model Context Protocol) endpoint: JSON-RPC over HTTP
      # POST, exposing the registered operations as tools. Responds 404 unless the
      # host enabled MCP.
      class McpController < BaseController
        before_action :require_mcp!

        # <tt>POST <admin path>/mcp</tt>.
        #
        # Authenticates the admin token, parses the JSON-RPC message from the raw
        # body and hands it to the MCP server. Renders the JSON-RPC answer, 202 with
        # no body for a notification, or 400 with a JSON-RPC parse error when the
        # body is not JSON.
        def create
          authenticate!
          WarpEngine::AdminApi::Mcp.ensure_available!

          message = parse_message
          return if performed?

          answer = WarpEngine::AdminApi::Mcp.server(principal: current_principal, base_url: engine_base_url)
                                           .handle(message)
          answer.nil? ? head(:accepted) : render(json: answer)
        end

        # <tt>GET</tt> and <tt>DELETE <admin path>/mcp</tt>.
        #
        # Responds 405 with <tt>Allow: POST</tt>; the endpoint keeps no streams or
        # sessions.
        def method_not_allowed
          response.headers["Allow"] = "POST"
          head :method_not_allowed
        end

        private

        def require_mcp!
          raise WarpEngine::AdminApi::Error.not_found unless admin_config.mcp?
        end

        def parse_message
          JSON.parse(request.raw_post.to_s, symbolize_names: true)
        rescue JSON::ParserError
          render json: { jsonrpc: "2.0", id: nil, error: { code: -32_700, message: "Parse error" } },
                 status: :bad_request
          nil
        end
      end
    end
  end
end
