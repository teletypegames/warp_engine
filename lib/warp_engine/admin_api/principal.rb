module WarpEngine
  module AdminApi
    # The authenticated caller of the Admin API: who owns it, which scopes it holds
    # and, when it came from one, the WarpEngine::ApplicationToken behind it.
    # Returned by the Authenticator (or the host's own authenticator).
    class Principal
      # The owning record (the host's token owner, e.g. a user), the frozen scope
      # strings, a display label and the application token, when there is one.
      attr_reader :owner, :scopes, :label, :token

      # Builds the principal of an authenticated WarpEngine::ApplicationToken +token+.
      def self.from_token(token)
        new(owner: token.owner, scopes: token.scopes, unrestricted: token.unrestricted?,
            label: token.name, token: token)
      end

      # [owner]        the record the caller acts for
      # [scopes]       the scopes it holds, strings or symbols
      # [unrestricted] whether it may grant unrestricted tokens
      # [label]        a display name
      # [token]        the WarpEngine::ApplicationToken it came from, if any
      def initialize(owner:, scopes:, unrestricted: false, label: nil, token: nil)
        @owner        = owner
        @scopes       = Array(scopes).map(&:to_s).freeze
        @unrestricted = unrestricted ? true : false
        @label        = label
        @token        = token
      end

      # Whether the caller is unrestricted.
      def unrestricted? = @unrestricted

      # Whether the caller holds +scope+.
      def scope?(scope)
        scopes.include?(scope.to_s)
      end

      # When the caller's token expires, or +nil+ when it never does or there is no token.
      def expires_at = token&.expires_at

      # The key the RateLimiter counts requests under: the token id, or the owner and label.
      def rate_limit_key
        return "token:#{token.id}" if token

        "principal:#{owner.class.name}:#{owner.try(:id)}:#{label}"
      end

      # The JSON form shown by <tt>GET /me</tt>: label, ownerType, ownerId, scopes,
      # unrestricted, tokenPrefix and expiresAt.
      def as_json(*)
        {
          label:        label,
          ownerType:    owner&.class&.name,
          ownerId:      owner.try(:id),
          scopes:       scopes,
          unrestricted: unrestricted?,
          tokenPrefix:  token&.token_prefix,
          expiresAt:    expires_at
        }
      end
    end
  end
end
