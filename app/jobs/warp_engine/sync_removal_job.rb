module WarpEngine
  # Background job that asks one sync peer to remove a release, or a whole
  # software, it got from this engine, through
  # WarpEngine::SyncPushService#push_removal. Queued by
  # WarpEngine::SyncService#dispatch_removal after a soft delete; a peer that
  # does not answer is tried again like WarpEngine::SyncPushJob.
  class SyncRemovalJob < ApplicationJob
    queue_as :default

    retry_on Sync::Transport::Unreachable, wait: :polynomially_longer, attempts: 5 do |job, error|
      Rails.logger.warn("[WarpEngine::Sync] gave up on removal #{job.arguments.first(3).inspect}: #{error.message}")
    end

    # Asks the peer +sync_peer_id+ to remove the release +version+ of the
    # software +name+ (the software when +version+ is +nil+), logging on the
    # WarpEngine::SyncEvent +event_id+ (when the events are on). A peer gone
    # in the meantime marks the event +skipped+.
    def perform(sync_peer_id, name, version = nil, event_id = nil)
      event = event_id && WarpEngine::SyncEvent.find_by(id: event_id)
      peer = WarpEngine::SyncPeer.kept.find_by(id: sync_peer_id)
      return event&.update!(status: "skipped", message: "the peer is gone") if peer.nil?

      WarpEngine::SyncPushService.new.push_removal(peer, name: name, version: version, event: event, attempt: executions)
    end
  end
end
