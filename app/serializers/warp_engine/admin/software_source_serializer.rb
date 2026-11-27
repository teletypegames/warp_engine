module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::SoftwareSource: id, software id, URL,
    # ref, the source check (+public+, +verifiedAt+, +verifyError+) and
    # timestamps.
    class SoftwareSourceSerializer < Blueprinter::Base
      identifier :id
      field :software_id, name: :softwareId
      fields :url, :ref, :public
      field :verified_at, name: :verifiedAt
      field :verify_error, name: :verifyError
      include Timestamps
    end
  end
end
