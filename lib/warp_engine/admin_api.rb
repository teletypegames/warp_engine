require "warp_engine/admin_api/scopes"
require "warp_engine/admin_api/configuration"
require "warp_engine/admin_api/principal"
require "warp_engine/admin_api/error"
require "warp_engine/admin_api/schema"
require "warp_engine/admin_api/result"
require "warp_engine/admin_api/operation"
require "warp_engine/admin_api/resource"
require "warp_engine/admin_api/context"
require "warp_engine/admin_api/runner"
require "warp_engine/admin_api/authenticator"
require "warp_engine/admin_api/rate_limiter"
require "warp_engine/admin_api/definitions/schemas"
require "warp_engine/admin_api/definitions/meta"
require "warp_engine/admin_api/definitions/catalog"
require "warp_engine/admin_api/definitions/vocabulary"
require "warp_engine/admin_api/definitions/statistics"
require "warp_engine/admin_api/definitions/pipelines"
require "warp_engine/admin_api/definitions/files"
require "warp_engine/admin_api/definitions/tokens"
require "warp_engine/admin_api/registry"
require "warp_engine/admin_api/open_api"
require "warp_engine/admin_api/mcp"
require "warp_engine/admin_api/docs_page"

module WarpEngine
  # The Admin API: everything the WarpEngine admin does, for programs, under
  # <tt>/api/admin/v1</tt>. Operations are declared once in the Definitions modules
  # and served three ways: as JSON over HTTP, as an OpenAPI 3.1 document (OpenApi,
  # with an optional Redoc page from DocsPage) and as MCP tools (Mcp).
  #
  # It is off by default; the host turns it on in the initializer:
  #
  #   WarpEngine.configure do
  #     admin_api do
  #       enable
  #     end
  #   end
  #
  # Callers authenticate with a bearer application token carrying admin scopes
  # (Scopes), or through the host's own Authenticator.
  module AdminApi
    # The major version of the Admin API, also in the URL prefix and the OpenAPI <tt>x-api-version</tt>.
    VERSION = 1

    # The response header that carries the Admin API version.
    HEADER = "WarpEngine-Admin-Api".freeze

    # The host's WarpEngine::AdminApi::Configuration, from <tt>WarpEngine.config.admin_api</tt>.
    def self.config
      WarpEngine.config.admin_api
    end

    # The URL prefix every Admin API route lives under: Operation::PREFIX.
    def self.url_path
      Operation::PREFIX
    end
  end
end
