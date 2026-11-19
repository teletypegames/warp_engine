module WarpEngine
  # Background job that runs one WarpEngine::LocalOperation through
  # WarpEngine::LocalComponentService#run (pulling images and starting
  # containers can take minutes). A failure ends in the operation, not in a retry.
  class LocalOperationJob < ApplicationJob
    queue_as :default

    # Runs the queued WarpEngine::LocalOperation +operation_id+; one that is
    # gone or not queued is left alone.
    def perform(operation_id)
      operation = WarpEngine::LocalOperation.find_by(id: operation_id, state: "queued")
      WarpEngine::LocalComponentService.new.run(operation) if operation
    end
  end
end
