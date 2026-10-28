module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::SoftwareStatus: id, key, label, position,
    # badge, +defaultVisible+, the number of kept softwares carrying it and
    # timestamps.
    class SoftwareStatusSerializer < Blueprinter::Base
      identifier :id
      fields :key, :label, :position, :badge
      field :default_visible, name: :defaultVisible
      field(:softwareCount) { |status| WarpEngine::Software.kept.where(status: status.key).count }
      include Timestamps
    end
  end
end
