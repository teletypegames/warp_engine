module WarpEngine
  class CiRepoSyncJob < ApplicationJob
    queue_as :default

    def perform
      CiRepoSyncService.new.sync_all
    end
  end
end
