module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::SoftwareImage: id, software and image ids,
    # default flag, position, the image URL and timestamps.
    class SoftwareImageSerializer < Blueprinter::Base
      identifier :id
      field :software_id, name: :softwareId
      field :image_id,    name: :imageId
      field :is_default,  name: :isDefault
      field :position
      field(:url) { |image| WarpEngine::Images.url_for(image.image_id) }
      include Timestamps
    end
  end
end
