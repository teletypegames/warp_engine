module WarpEngine
  # Background job that mirrors the CI server's repositories into
  # WarpEngine::Pipeline records.
  class PipelineSyncJob < ApplicationJob
    queue_as :default

    # Runs WarpEngine::PipelineSyncService#sync_all: creates and updates a
    # pipeline for every CI repository and deactivates the ones that are gone.
    def perform
      PipelineSyncService.new.sync_all
    end
  end
end
