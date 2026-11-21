module WarpEngine
  # Background job that tells the parent engine about a published fork
  # (WarpEngine::ForkService#announce). Queued after every publish of a fork
  # while WarpEngine::Forks.announce? holds; retried on network errors.
  class ForkAnnounceJob < ApplicationJob
    queue_as :default

    retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError, wait: 5.minutes, attempts: 3

    # Announces the kept WarpEngine::Software +software_id+ and logs the answer.
    def perform(software_id)
      software = WarpEngine::Software.kept.find_by(id: software_id)
      status = software && WarpEngine::ForkService.new.announce(software)
      Rails.logger.info("[WarpEngine::Forks] announced #{software.name} to #{software.fork_of_engine}: HTTP #{status}") if status
    end
  end
end
