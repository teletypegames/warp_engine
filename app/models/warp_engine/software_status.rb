module WarpEngine
  class SoftwareStatus < ApplicationRecord
    self.table_name = "software_statuses"

    include ShelfRefreshing

    KEY_FORMAT = /\A[a-z0-9_-]+\z/

    DEFAULTS = [
      { key: "released",    label: "Released",       position: 1, default_visible: true,  badge: "released" },
      { key: "demo",        label: "Demo",           position: 2, default_visible: true,  badge: "demo" },
      { key: "development", label: "In development", position: 3, default_visible: false, badge: "development" },
      { key: "archived",    label: "Archived",       position: 4, default_visible: true,  badge: nil }
    ].freeze

    validates :key, presence: true, uniqueness: true, length: { maximum: 32 }, format: { with: KEY_FORMAT }
    validates :label, presence: true, length: { maximum: 128 }
    validates :position, numericality: { only_integer: true }

    scope :ordered, -> { order(:position, :key) }

    def self.seed_defaults!
      return unless none?

      DEFAULTS.each { |attributes| create!(attributes) }
    end

    def self.ensured
      seed_defaults!
      ordered
    end

    def self.keys
      ensured.pluck(:key)
    end

    def self.default_visible_keys
      ensured.where(default_visible: true).pluck(:key)
    end
  end
end
