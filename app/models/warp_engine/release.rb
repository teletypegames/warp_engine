module WarpEngine
  class Release < ApplicationRecord
    self.table_name = "releases"

    include SoftDeletable

    belongs_to :software
    has_many :downloads, -> { kept }
    has_many :release_assets, -> { kept }

    accepts_nested_attributes_for :release_assets, allow_destroy: true

    validates :version, presence: true
    validates :version, uniqueness: { scope: :software_id }

    validate :c64_cannot_be_web_playable

    def self.latest_non_dev(releases)
      sorted = releases.sort_by { |r| [ r.created_at || Time.at(0), r.id ] }.reverse
      candidates = sorted.reject { |r| r.version.to_s.start_with?("dev-") }
      candidates.empty? ? sorted.first : candidates.first
    end

    def c64_cannot_be_web_playable
      return unless software&.platform == "c64"

      has_html = release_assets.reject(&:marked_for_destruction?).any? { |a| a.kind == "html" }
      if has_html
        errors.add(:base, "C64 releases cannot be web playable (download only)")
      end
    end

    ActiveSupport.run_load_hooks(:warp_engine_release, self)
  end
end
