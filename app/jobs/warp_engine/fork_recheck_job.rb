module WarpEngine
  # Background job that verifies the fork links that are due again
  # (WarpEngine::ForkService#recheck_due). The engine does not schedule it:
  # the host runs it periodically with its job backend (e.g. a Solid Queue
  # recurring task).
  class ForkRecheckJob < ApplicationJob
    queue_as :default

    # Rechecks the due fork links and logs how many.
    def perform
      count = WarpEngine::ForkService.new.recheck_due
      Rails.logger.info("[WarpEngine::Forks] #{count} fork links rechecked") if count.positive?
    end
  end
end
