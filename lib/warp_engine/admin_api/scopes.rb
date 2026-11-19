module WarpEngine
  module AdminApi
    # The application token scopes that open the Admin API.
    module Scopes
      # Reads every enabled resource.
      READ   = "admin:read".freeze
      # Creates, changes and deletes records of every enabled resource.
      WRITE  = "admin:write".freeze
      # Manages application tokens and device sign-ins.
      TOKENS = "admin:tokens".freeze
      # Pairs with this engine: manages the caller's own inbound sync peers
      # (the +sync_pairings+ resource), nothing else.
      PAIR   = "sync:pair".freeze
      # Every admin scope; a token holding any of them is an admin token.
      ALL    = [ READ, WRITE, TOKENS, PAIR ].freeze
    end
  end
end
