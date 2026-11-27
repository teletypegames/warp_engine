module WarpEngine
  # Background job that checks one software source
  # (WarpEngine::SourceVerifyService#verify), or, without an id, every source
  # that is due (#verify_due). The engine queues it after a publish; the host
  # runs it without an id periodically (e.g. a Solid Queue recurring task).
  class SourceVerifyJob < ApplicationJob
    queue_as :default

    # Checks the WarpEngine::SoftwareSource +source_id+, or every due source when +nil+.
    def perform(source_id = nil)
      service = WarpEngine::SourceVerifyService.new
      if source_id
        service.verify(WarpEngine::SoftwareSource.kept.find_by(id: source_id))
      else
        count = service.verify_due
        Rails.logger.info("[WarpEngine::Forks] #{count} sources checked") if count.positive?
      end
    end
  end
end
