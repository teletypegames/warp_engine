module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::ApplicationToken: id, name, token prefix,
    # owner, scopes, +unrestricted+, expiry, last use and timestamps. Never the
    # token or its digest.
    class ApplicationTokenSerializer < Blueprinter::Base
      identifier :id
      field :name
      field :token_prefix, name: :tokenPrefix
      field :owner_type,   name: :ownerType
      field :owner_id,     name: :ownerId
      field(:scopes) { |token| Array(token.scopes) }
      field(:unrestricted) { |token| token.unrestricted? }
      field :expires_at,   name: :expiresAt
      field :last_used_at, name: :lastUsedAt
      include Timestamps
    end
  end
end
