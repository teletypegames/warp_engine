module WarpEngine
  module AdminApi
    class Principal
      attr_reader :owner, :scopes, :label, :token

      def self.from_token(token)
        new(owner: token.owner, scopes: token.scopes, unrestricted: token.unrestricted?,
            label: token.name, token: token)
      end

      def initialize(owner:, scopes:, unrestricted: false, label: nil, token: nil)
        @owner        = owner
        @scopes       = Array(scopes).map(&:to_s).freeze
        @unrestricted = unrestricted ? true : false
        @label        = label
        @token        = token
      end

      def unrestricted? = @unrestricted

      def scope?(scope)
        scopes.include?(scope.to_s)
      end

      def expires_at = token&.expires_at

      def rate_limit_key
        return "token:#{token.id}" if token

        "principal:#{owner.class.name}:#{owner.try(:id)}:#{label}"
      end

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
