module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::SyncServer: id, label, host, the prefix of
    # its token (never the token), active flag, last push time and error, and
    # timestamps.
    class SyncServerSerializer < Blueprinter::Base
      identifier :id
      fields :label, :host, :active
      field :secret_prefix,  name: :secretPrefix
      field :last_synced_at, name: :lastSyncedAt
      field :last_error,     name: :lastError
      include Timestamps
    end
  end
end
