module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::ForkLink: id, the software (id and
    # name), the child engine, name and title, the moderation status, the
    # newest check and timestamps.
    class ForkLinkSerializer < Blueprinter::Base
      identifier :id
      field :software_id, name: :softwareId
      field(:softwareName) { |link| link.software&.name }
      field :child_engine, name: :childEngine
      field :child_name,   name: :childName
      field :child_title,  name: :childTitle
      field :status
      field :checked_at,   name: :checkedAt
      field :last_error,   name: :lastError
      include Timestamps
    end
  end
end
