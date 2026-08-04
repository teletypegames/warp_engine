module WarpEngine
  class Release < ApplicationRecord
    self.table_name = "releases"

    belongs_to :software
    has_many :downloads
    has_many :release_assets

    accepts_nested_attributes_for :release_assets, allow_destroy: true

    validates :version, presence: true
    validates :version, uniqueness: { scope: :software_id }

    default_scope { where(deleted_at: nil) }

    validate :c64_cannot_be_web_playable

    def c64_cannot_be_web_playable
      return unless software&.platform == "c64"

      has_html = release_assets.reject(&:marked_for_destruction?).any? { |a| a.kind == "html" }
      if has_html
        errors.add(:base, "C64 releases cannot be web playable (download only)")
      end
    end

    def self.ransackable_attributes(auth_object = nil)
      %w[created_at deleted_at id software_id updated_at version]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[downloads release_assets software]
    end

    ActiveSupport.run_load_hooks(:warp_engine_release, self)
  end
end
