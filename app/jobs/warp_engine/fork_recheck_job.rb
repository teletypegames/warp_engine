module WarpEngine
  # Background job that verifies the announced forks that are due again
  # (WarpEngine::ForkService#recheck_due). The engine does not schedule it:
  # the host runs it periodically with its job backend (e.g. a Solid Queue
  # recurring task).
  class ForkRecheckJob < ApplicationJob
    queue_as :default

    # Rechecks the due announced forks and logs how many.
    def perform
      count = WarpEngine::ForkService.new.recheck_due
      Rails.logger.info("[WarpEngine::Forks] #{count} announced forks rechecked") if count.positive?
    end
  end
end
