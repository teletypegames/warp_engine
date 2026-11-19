module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::SyncPeer: id, label, transport and its
    # options, the prefix of its secret (never the secret), both direction
    # switches, its own channels, who paired it, the prefix of its inbound
    # token, last push time and error, and timestamps.
    class SyncPeerSerializer < Blueprinter::Base
      identifier :id
      fields :label, :transport
      field(:transportOptions) { |peer| peer.transport_options.to_h }
      field :secret_prefix,    name: :secretPrefix
      field :outbound_enabled, name: :outboundEnabled
      field :inbound_enabled,  name: :inboundEnabled
      field(:allowedChannels) { |peer| peer.channels }
      field(:createdBy) { |peer| peer.created_by_id && { type: peer.created_by_type, id: peer.created_by_id } }
      field(:inboundTokenPrefix) { |peer| peer.inbound_token&.token_prefix }
      field :last_synced_at,   name: :lastSyncedAt
      field :last_error,       name: :lastError
      include Timestamps
    end
  end
end
