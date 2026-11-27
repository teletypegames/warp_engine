module WarpEngine
  # Background job that mirrors the CI server's repositories into
  # WarpEngine::CiRepository records.
  class CiRepositorySyncJob < ApplicationJob
    queue_as :default

    # Runs WarpEngine::CiRepositorySyncService#sync_all: creates and updates a
    # record for every CI repository and deactivates the ones that are gone.
    def perform
      CiRepositorySyncService.new.sync_all
    end
  end
end
