module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::ExternalLink: id, software id, label, URL
    # and timestamps.
    class ExternalLinkSerializer < Blueprinter::Base
      identifier :id
      field :software_id, name: :softwareId
      fields :label, :url
      include Timestamps
    end
  end
end
