module WarpEngine
  # Background job that queues the pushes a sync peer may be missing
  # (WarpEngine::SyncService#backfill), from the admin.
  class SyncBackfillJob < ApplicationJob
    queue_as :default

    # Queues the pushes to the peer +sync_peer_id+: the newest allowed
    # release of every software (or of the software named +software+), or
    # every allowed release when +all+. Does nothing for a peer gone in the
    # meantime or while outbound sync is off; logs the releases it skipped.
    def perform(sync_peer_id, software = nil, all = false)
      peer = WarpEngine::SyncPeer.kept.find_by(id: sync_peer_id)
      return if peer.nil?

      result = WarpEngine::SyncService.new.backfill(peer, software: software, all: all)
      Rails.logger.info("[WarpEngine::Sync] #{peer.label}: #{result.queued} queued, #{result.skipped.size} skipped")
    rescue WarpEngine::SyncService::DisabledError => e
      Rails.logger.warn("[WarpEngine::Sync] #{peer&.label}: #{e.message}")
    end
  end
end
