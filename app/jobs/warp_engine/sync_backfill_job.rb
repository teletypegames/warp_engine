module WarpEngine
  # Background job that queues the pushes a sync server may be missing
  # (WarpEngine::SyncService#backfill), from the admin or the Admin API.
  class SyncBackfillJob < ApplicationJob
    queue_as :default

    # Queues the pushes to the server +sync_server_id+: the newest allowed
    # release of every software (or of the software named +software+), or
    # every allowed release when +all+. Does nothing for a server gone in the
    # meantime or while sync is off; logs the releases it skipped.
    def perform(sync_server_id, software = nil, all = false)
      server = WarpEngine::SyncServer.kept.find_by(id: sync_server_id)
      return if server.nil?

      result = WarpEngine::SyncService.new.backfill(server, software: software, all: all)
      Rails.logger.info("[WarpEngine::Sync] #{server.label}: #{result.queued} queued, #{result.skipped.size} skipped")
    rescue WarpEngine::SyncService::DisabledError => e
      Rails.logger.warn("[WarpEngine::Sync] #{server&.label}: #{e.message}")
    end
  end
end
