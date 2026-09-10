module WarpEngine
  class SoftwareStatus < ApplicationRecord
    self.table_name = "software_statuses"

    KEY_FORMAT = /\A[a-z0-9_-]+\z/

    validates :key, presence: true, uniqueness: true, length: { maximum: 32 }, format: { with: KEY_FORMAT }
    validates :label, presence: true, length: { maximum: 128 }
    validates :position, numericality: { only_integer: true }

    scope :ordered, -> { order(:position, :key) }

    def self.keys
      ordered.pluck(:key)
    end

    def self.default_visible_keys
      ordered.where(default_visible: true).pluck(:key)
    end
  end
end
