module WarpEngine
  # Base class of the engine's jobs. Retries a job three times, 30 seconds
  # apart, on WarpEngine::CI::ConnectionError, and discards it (logging the
  # error) on WarpEngine::CI::ApiError or WarpEngine::CI::NotConfigured.
  class ApplicationJob < ActiveJob::Base
    retry_on CI::ConnectionError, wait: 30.seconds, attempts: 3
    discard_on CI::ApiError, CI::NotConfigured do |job, error|
      Rails.logger.error("[#{job.class.name}] discarded: #{error.message}")
    end
  end
end
