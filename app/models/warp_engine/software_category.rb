module WarpEngine
  class SoftwareCategory < ApplicationRecord
    self.table_name = "software_categories"

    validates :key, presence: true, uniqueness: true, length: { maximum: 64 }
    validates :label, presence: true, length: { maximum: 128 }
    validates :position, numericality: { only_integer: true }

    scope :ordered, -> { order(:position, :key) }

    def self.register(key)
      return nil if key.blank?

      find_or_create_by!(key: key) do |category|
        category.label = key
        category.needs_review = true
        category.position = maximum(:position).to_i + 1
      end
    end
  end
end
