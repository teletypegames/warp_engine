module WarpEngine
  # Background job that runs one WarpEngine::LocalTask through
  # WarpEngine::LocalProviderService#run (pulling images and starting
  # containers can take minutes). A failure ends in the task, not in a retry.
  class LocalTaskJob < ApplicationJob
    queue_as :default

    # Runs the queued WarpEngine::LocalTask +task_id+; one that is
    # gone or not queued is left alone.
    def perform(task_id)
      task = WarpEngine::LocalTask.find_by(id: task_id, state: "queued")
      WarpEngine::LocalProviderService.new.run(task) if task
    end
  end
end
