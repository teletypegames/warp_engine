module WarpEngine
  module Admin
    class ReleaseSerializer < Blueprinter::Base
      identifier :id
      field :software_id, name: :softwareId
      field :version
      field(:assets) { |release| ReleaseAssetSerializer.render_as_hash(release.release_assets.sort_by(&:kind)) }
      include Timestamps
    end
  end
end
