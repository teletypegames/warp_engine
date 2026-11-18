module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::SyncEvent: id, peer id, software id, direction,
    # status, the release (software name, platform, version, release id), the
    # step, HTTP status and message, the files and bytes sent, the duration,
    # the attempt, the token prefix of an inbound push, and timestamps.
    class SyncEventSerializer < Blueprinter::Base
      identifier :id
      field :sync_peer_id, name: :syncPeerId
      field :software_id,  name: :softwareId
      fields :direction, :status, :platform, :version, :step, :message, :bytes, :attempt
      field :software_name, name: :softwareName
      field :release_id,    name: :releaseId
      field :http_status,   name: :httpStatus
      field :files_count,   name: :filesCount
      field :duration_ms,   name: :durationMs
      field :token_prefix,  name: :tokenPrefix
      include Timestamps
    end
  end
end
