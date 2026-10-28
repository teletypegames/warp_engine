module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::ReleaseAsset: id, release id, kind, path
    # and timestamps.
    class ReleaseAssetSerializer < Blueprinter::Base
      identifier :id
      field :release_id, name: :releaseId
      fields :kind, :path
      include Timestamps
    end
  end
end
