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
  module AdminApi
    VERSION = 1

    HEADER = "WarpEngine-Admin-Api".freeze

    def self.config
      WarpEngine.config.admin_api
    end

    def self.url_path
      Operation::PREFIX
    end
  end
end
