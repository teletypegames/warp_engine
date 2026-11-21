module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::Software: id, name, title, author,
    # descriptions, license, platform, status, category, highlighted flag,
    # shelf name, owner, the fork switch and parent, and timestamps.
    class SoftwareSerializer < Blueprinter::Base
      identifier :id
      fields :name, :title, :author, :desc, :story, :license, :platform, :status, :category, :highlighted
      field :shelf_name, name: :shelfName
      field :owner_type, name: :ownerType
      field :owner_id,   name: :ownerId
      field :forks_allowed,   name: :forksAllowed
      field :fork_of_engine,  name: :forkOfEngine
      field :fork_of_name,    name: :forkOfName
      field :fork_of_version, name: :forkOfVersion
      field :fork_of_repo,    name: :forkOfRepo
      include Timestamps
    end
  end
end
