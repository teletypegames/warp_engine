module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::Software: id, name, title, author,
    # descriptions, license, platform, status, category, highlighted flag,
    # shelf name, owner and timestamps.
    class SoftwareSerializer < Blueprinter::Base
      identifier :id
      fields :name, :title, :author, :desc, :story, :license, :platform, :status, :category, :highlighted
      field :shelf_name, name: :shelfName
      field :owner_type, name: :ownerType
      field :owner_id,   name: :ownerId
      include Timestamps
    end
  end
end
