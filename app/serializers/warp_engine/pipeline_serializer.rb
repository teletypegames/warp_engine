module WarpEngine
  class PipelineSerializer < Blueprinter::Base
    field :id
    field :repo_owner,           name: :repoOwner
    field :repo_name,            name: :repoName
    field :platform
    field :active
    field :last_pipeline_status, name: :lastPipelineStatus
    field :last_pipeline_at,     name: :lastPipelineAt

    field(:repoId)       { |pipeline| pipeline.remote_repo_id }
    field(:softwareName) { |pipeline| pipeline.software&.name }
  end
end
