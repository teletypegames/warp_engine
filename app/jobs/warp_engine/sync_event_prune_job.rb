module WarpEngine
  # Background job that deletes the sync events older than
  # WarpEngine::Sync::Configuration#event_retention_days
  # (WarpEngine::SyncService#prune_events). The engine does not schedule it:
  # the host runs it periodically with its job backend (e.g. a Solid Queue
  # recurring task).
  class SyncEventPruneJob < ApplicationJob
    queue_as :default

    # Deletes the old events and logs how many.
    def perform
      count = WarpEngine::SyncService.new.prune_events
      Rails.logger.info("[WarpEngine::Sync] #{count} old sync events deleted") if count.positive?
    end
  end
end
