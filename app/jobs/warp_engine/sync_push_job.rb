module WarpEngine
  # Background job that pushes one release to one sync server through
  # WarpEngine::SyncPushService. Queued by WarpEngine::SyncService after a
  # publish or a backfill; a server that does not answer is tried again, five
  # times in all with a growing wait, then the job gives up (the event and
  # the server's +last_error+ say why).
  class SyncPushJob < ApplicationJob
    queue_as :default

    retry_on Sync::ConnectionError, wait: :polynomially_longer, attempts: 5 do |job, error|
      Rails.logger.warn("[WarpEngine::Sync] gave up on #{job.arguments.inspect}: #{error.message}")
    end

    # Pushes the kept release +release_id+ to the server +sync_server_id+,
    # logging on the WarpEngine::SyncEvent +event_id+ (when the events are
    # on). A release or server gone in the meantime marks the event +skipped+.
    def perform(release_id, sync_server_id, event_id = nil)
      event = event_id && WarpEngine::SyncEvent.find_by(id: event_id)
      release = WarpEngine::Release.kept.find_by(id: release_id)
      server = WarpEngine::SyncServer.kept.find_by(id: sync_server_id)
      return event&.update!(status: "skipped", message: "the release or the server is gone") if release.nil? || server.nil?

      WarpEngine::SyncPushService.new.push(release, server, event: event, attempt: executions)
    end
  end
end
