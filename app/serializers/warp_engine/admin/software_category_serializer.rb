module WarpEngine
  module Admin
    class SoftwareCategorySerializer < Blueprinter::Base
      identifier :id
      fields :key, :label, :position
      field :needs_review, name: :needsReview
      field(:softwareCount) { |category| WarpEngine::Software.kept.where(category: category.key).count }
      include Timestamps
    end
  end
end
