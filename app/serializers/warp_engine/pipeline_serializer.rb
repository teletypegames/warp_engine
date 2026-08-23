module WarpEngine
  class PipelineSerializer < Blueprinter::Base
    field :id
    field :repo_owner
    field :repo_name
    field :platform
    field :active
    field :last_pipeline_status
    field :last_pipeline_at

    field(:repo_id)            { |pipeline| pipeline.remote_repo_id }
    field(:woodpecker_repo_id) { |pipeline| pipeline.remote_repo_id }
    field(:software_name)      { |pipeline| pipeline.software&.name }
  end
end
