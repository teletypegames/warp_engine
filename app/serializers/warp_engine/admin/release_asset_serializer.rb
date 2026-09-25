module WarpEngine
  module Admin
    class ReleaseAssetSerializer < Blueprinter::Base
      identifier :id
      field :release_id, name: :releaseId
      fields :kind, :path
      include Timestamps
    end
  end
end
