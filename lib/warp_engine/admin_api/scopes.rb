module WarpEngine
  module AdminApi
    module Scopes
      READ   = "admin:read".freeze
      WRITE  = "admin:write".freeze
      TOKENS = "admin:tokens".freeze
      ALL    = [ READ, WRITE, TOKENS ].freeze
    end
  end
end
