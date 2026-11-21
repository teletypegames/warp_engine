module WarpEngine
  # Background job that reads an announced fork back from its engine and
  # records it (WarpEngine::ForkService#verify). Queued by
  # <tt>POST /api/forks</tt>.
  class ForkVerifyJob < ApplicationJob
    queue_as :default

    # Verifies the fork +name+ on the engine +engine+.
    def perform(engine, name)
      link = WarpEngine::ForkService.new.verify(engine: engine, name: name)
      Rails.logger.info("[WarpEngine::Forks] #{name} on #{engine}: #{link ? link.status : 'not confirmed'}")
    end
  end
end
