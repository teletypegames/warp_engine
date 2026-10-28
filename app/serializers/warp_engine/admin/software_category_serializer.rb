module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::SoftwareCategory: id, key, label,
    # position, +needsReview+, the number of kept softwares carrying it and
    # timestamps.
    class SoftwareCategorySerializer < Blueprinter::Base
      identifier :id
      fields :key, :label, :position
      field :needs_review, name: :needsReview
      field(:softwareCount) { |category| WarpEngine::Software.kept.where(category: category.key).count }
      include Timestamps
    end
  end
end
