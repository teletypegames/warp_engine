module WarpEngine
  # A category a software may carry (table +software_categories+): its
  # +key+ (the value of WarpEngine::Software +category+), a display +label+
  # and +position+ (scope +ordered+), and +needs_review+ for categories
  # registered automatically.
  class SoftwareCategory < ApplicationRecord
    self.table_name = "software_categories"

    validates :key, presence: true, uniqueness: true, length: { maximum: 64 }
    validates :label, presence: true, length: { maximum: 128 }
    validates :position, numericality: { only_integer: true }

    scope :ordered, -> { order(:position, :key) }

    # Returns the category with +key+, creating it at the end of the order with
    # the key as its label and +needs_review+ set when there is none. Returns
    # +nil+ for a blank key.
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
