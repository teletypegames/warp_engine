module WarpEngine
  class ApplicationJob < ActiveJob::Base
    retry_on WoodpeckerClient::ConnectionError, wait: 30.seconds, attempts: 3
    discard_on WoodpeckerClient::ApiError do |job, error|
      Rails.logger.error("[#{job.class.name}] discarded: #{error.message}")
    end
  end
end
