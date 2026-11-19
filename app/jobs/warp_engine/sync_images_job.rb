module WarpEngine
  # Background job that sends one software's gallery to one sync peer
  # through WarpEngine::SyncPushService#push_images. Queued by
  # WarpEngine::SyncService#dispatch_images after the images changed, a few
  # seconds later so a run of changes goes as one; a peer that does not
  # answer is tried again like WarpEngine::SyncPushJob.
  class SyncImagesJob < ApplicationJob
    queue_as :default

    retry_on Sync::Transport::Unreachable, wait: :polynomially_longer, attempts: 5 do |job, error|
      Rails.logger.warn("[WarpEngine::Sync] gave up on images #{job.arguments.first(2).inspect}: #{error.message}")
    end

    # Sends the gallery of the kept software +software_id+ to the peer
    # +sync_peer_id+, logging on the WarpEngine::SyncEvent +event_id+ (when
    # the events are on). A software or peer gone in the meantime marks the
    # event +skipped+.
    def perform(software_id, sync_peer_id, event_id = nil)
      event = event_id && WarpEngine::SyncEvent.find_by(id: event_id)
      software = WarpEngine::Software.kept.find_by(id: software_id)
      peer = WarpEngine::SyncPeer.kept.find_by(id: sync_peer_id)
      return event&.update!(status: "skipped", message: "the software or the peer is gone") if software.nil? || peer.nil?

      WarpEngine::SyncPushService.new.push_images(software, peer, event: event, attempt: executions)
    end
  end
end
