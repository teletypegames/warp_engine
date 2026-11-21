module WarpEngine
  # Background job that checks one source link
  # (WarpEngine::SourceVerifyService#verify), or, without an id, every source
  # that is due (#verify_due). The engine queues it after a publish; the host
  # runs it without an id periodically (e.g. a Solid Queue recurring task).
  class SourceVerifyJob < ApplicationJob
    queue_as :default

    # Checks the WarpEngine::ExternalLink +link_id+, or every due source when +nil+.
    def perform(link_id = nil)
      service = WarpEngine::SourceVerifyService.new
      if link_id
        service.verify(WarpEngine::ExternalLink.kept.find_by(id: link_id))
      else
        count = service.verify_due
        Rails.logger.info("[WarpEngine::Forks] #{count} source links checked") if count.positive?
      end
    end
  end
end
