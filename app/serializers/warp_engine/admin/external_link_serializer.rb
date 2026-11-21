module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::ExternalLink: id, software id, label, URL,
    # kind, ref, the source check (+public+, +verifiedAt+, +verifyError+) and
    # timestamps.
    class ExternalLinkSerializer < Blueprinter::Base
      identifier :id
      field :software_id, name: :softwareId
      fields :label, :url, :kind, :ref, :public
      field :verified_at, name: :verifiedAt
      field :verify_error, name: :verifyError
      include Timestamps
    end
  end
end
