module WarpEngine
  module Admin
    class ExternalLinkSerializer < Blueprinter::Base
      identifier :id
      field :software_id, name: :softwareId
      fields :label, :url
      include Timestamps
    end
  end
end
