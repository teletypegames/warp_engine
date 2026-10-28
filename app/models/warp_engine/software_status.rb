module WarpEngine
  # A status a software may carry (table +software_statuses+): its +key+ (the
  # value of WarpEngine::Software +status+), a display +label+ and +position+
  # (scope +ordered+), whether clients list it by default
  # (+default_visible+) and a +badge+ style hint. The table seeds itself with
  # DEFAULTS when empty. Changes refresh every shelf.
  class SoftwareStatus < ApplicationRecord
    self.table_name = "software_statuses"

    include ShelfRefreshing

    # Allowed characters of a status key: lower-case letters, digits,
    # underscore and hyphen.
    KEY_FORMAT = /\A[a-z0-9_-]+\z/

    # The statuses seeded into an empty table: released, demo, development and
    # archived.
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

    # Creates DEFAULTS when the table is empty; does nothing otherwise.
    def self.seed_defaults!
      return unless none?

      DEFAULTS.each { |attributes| create!(attributes) }
    end

    # Seeds the defaults when needed and returns every status in display order.
    def self.ensured
      seed_defaults!
      ordered
    end

    # Returns every status key in display order.
    def self.keys
      ensured.pluck(:key)
    end

    # Returns the keys of the statuses listed by default, in display order.
    def self.default_visible_keys
      ensured.where(default_visible: true).pluck(:key)
    end
  end
end
