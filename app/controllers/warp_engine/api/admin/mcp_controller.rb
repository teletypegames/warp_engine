module WarpEngine
  module Api
    module Admin
      class McpController < BaseController
        before_action :require_mcp!

        def create
          authenticate!
          WarpEngine::AdminApi::Mcp.ensure_available!

          message = parse_message
          return if performed?

          answer = WarpEngine::AdminApi::Mcp.server(principal: current_principal, base_url: engine_base_url)
                                           .handle(message)
          answer.nil? ? head(:accepted) : render(json: answer)
        end

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
