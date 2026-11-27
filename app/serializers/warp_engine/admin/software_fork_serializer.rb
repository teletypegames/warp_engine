module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::SoftwareFork: id, the software (id and
    # name), the fork's engine URL, name and title, the moderation status, the
    # newest check and timestamps.
    class SoftwareForkSerializer < Blueprinter::Base
      identifier :id
      field :software_id, name: :softwareId
      field(:softwareName) { |link| link.software&.name }
      field :engine_url, name: :engineUrl
      field :name
      field :title
      field :status
      field :checked_at,   name: :checkedAt
      field :last_error,   name: :lastError
      include Timestamps
    end
  end
end
