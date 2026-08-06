module WarpEngine
  class PipelineSyncJob < ApplicationJob
    queue_as :default

    def perform
      PipelineSyncService.new.sync_all
    end
  end
end
