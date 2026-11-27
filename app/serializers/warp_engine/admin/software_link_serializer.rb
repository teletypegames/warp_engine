module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::SoftwareLink: id, software id, label, URL
    # and timestamps.
    class SoftwareLinkSerializer < Blueprinter::Base
      identifier :id
      field :software_id, name: :softwareId
      fields :label, :url
      include Timestamps
    end
  end
end
