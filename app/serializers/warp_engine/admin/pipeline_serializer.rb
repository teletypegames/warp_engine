module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::Pipeline: id, CI repository id, owner,
    # name and full name, platform, active flag, software id, last run status
    # and time, and timestamps.
    class PipelineSerializer < Blueprinter::Base
      identifier :id
      field(:repoId) { |pipeline| pipeline.remote_repo_id }
      field :repo_owner, name: :repoOwner
      field :repo_name,  name: :repoName
      field(:fullName) { |pipeline| pipeline.full_name }
      fields :platform, :active
      field :software_id,          name: :softwareId
      field :last_pipeline_status, name: :lastPipelineStatus
      field :last_pipeline_at,     name: :lastPipelineAt
      include Timestamps
    end
  end
end
