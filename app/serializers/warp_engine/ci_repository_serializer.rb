module WarpEngine
  # CI API view of a WarpEngine::CiRepository: id, repository owner and name,
  # platform, active flag, last run status and time, CI repository id and the
  # linked software's name.
  class CiRepositorySerializer < Blueprinter::Base
    field :id
    field :repo_owner,           name: :repoOwner
    field :repo_name,            name: :repoName
    field :platform
    field :active
    field :last_pipeline_status, name: :lastPipelineStatus
    field :last_pipeline_at,     name: :lastPipelineAt

    field(:repoId)       { |repository| repository.remote_repo_id }
    field(:softwareName) { |repository| repository.software&.name }
  end
end
