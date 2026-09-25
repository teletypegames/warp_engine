module WarpEngine
  module Admin
    class SoftwareStatusSerializer < Blueprinter::Base
      identifier :id
      fields :key, :label, :position, :badge
      field :default_visible, name: :defaultVisible
      field(:softwareCount) { |status| WarpEngine::Software.kept.where(status: status.key).count }
      include Timestamps
    end
  end
end
