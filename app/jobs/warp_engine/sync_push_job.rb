module WarpEngine
  # Background job that pushes one release to one sync peer through
  # WarpEngine::SyncPushService. Queued by WarpEngine::SyncService after a
  # publish or a run; a peer that does not answer is tried again, five times
  # in all with a growing wait, then the job gives up (the event and the
  # peer's +last_error+ say why).
  class SyncPushJob < ApplicationJob
    queue_as :default

    retry_on Sync::Transport::Unreachable, wait: :polynomially_longer, attempts: 5 do |job, error|
      Rails.logger.warn("[WarpEngine::Sync] gave up on #{job.arguments.first(2).inspect}: #{error.message}")
    end

    # Pushes the kept release +release_id+ to the peer +sync_peer_id+,
    # logging on the WarpEngine::SyncEvent +event_id+ (when the events are
    # on), through the filter of +criteria+ (a WarpEngine::Sync::Criteria as
    # a Hash, from a run; it also says whether to skip what the peer has)
    # or the configured one. A release or peer gone in the meantime marks
    # the event +skipped+.
    def perform(release_id, sync_peer_id, event_id = nil, criteria = nil)
      event = event_id && WarpEngine::SyncEvent.find_by(id: event_id)
      release = WarpEngine::Release.kept.find_by(id: release_id)
      peer = WarpEngine::SyncPeer.kept.find_by(id: sync_peer_id)
      return event&.update!(status: "skipped", message: "the release or the peer is gone") if release.nil? || peer.nil?

      run = criteria.present? ? WarpEngine::Sync::Criteria.from_h(criteria) : nil
      WarpEngine::SyncPushService.new.push(release, peer, event: event, attempt: executions, filter: run&.filter,
                                                          skip_existing: run&.skip_existing == true)
    end
  end
end
