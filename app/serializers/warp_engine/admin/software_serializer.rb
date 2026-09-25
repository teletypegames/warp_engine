module WarpEngine
  module Admin
    class SoftwareSerializer < Blueprinter::Base
      identifier :id
      fields :name, :title, :author, :desc, :story, :license, :platform, :status, :category, :highlighted
      field :owner_type, name: :ownerType
      field :owner_id,   name: :ownerId
      include Timestamps
    end
  end
end
