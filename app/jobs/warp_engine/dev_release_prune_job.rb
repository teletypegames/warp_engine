module WarpEngine
  # Background job that removes the stale development builds with
  # WarpEngine::DevReleaseService, using the configured
  # WarpEngine::Configuration#dev_release_ttl_days and
  # WarpEngine::Configuration#dev_release_keep_branches. The engine does not
  # schedule it: the host runs it periodically with its job backend (e.g. a
  # Solid Queue recurring task).
  class DevReleasePruneJob < ApplicationJob
    queue_as :default

    # Prunes the development builds for real and logs each one removed.
    def perform
      report = DevReleaseService.new.prune(dry_run: false)
      report.lines.each { |line| Rails.logger.info("[WarpEngine] development build removed: #{line}") }
    end
  end
end
