module WarpEngine
  # One version of a software (table +releases+), unique per software. Has
  # many kept +downloads+ and +release_assets+ (editable as nested
  # attributes). A release of a download-only platform may not have an +html+
  # asset. Soft-deletable; saving or deleting one refreshes the outlets (shelves) of the
  # software's platform.
  class Release < ApplicationRecord
    self.table_name = "releases"

    include SoftDeletable
    include OutletRefreshing

    belongs_to :software
    has_many :downloads, -> { kept }
    has_many :release_assets, -> { kept }

    accepts_nested_attributes_for :release_assets, allow_destroy: true

    validates :version, presence: true
    validates :version, uniqueness: { scope: :software_id }

    validate :download_only_platform_cannot_be_web_playable

    # Returns the newest of +releases+ (by creation time, then id) whose version
    # does not start with <tt>dev-</tt>, or the newest of all when every one
    # does; +nil+ for an empty list.
    def self.latest_non_dev(releases)
      sorted = releases.sort_by { |r| [ r.created_at || Time.at(0), r.id ] }.reverse
      candidates = sorted.reject { |r| r.version.to_s.start_with?("dev-") }
      candidates.empty? ? sorted.first : candidates.first
    end

    # Returns the software's platform, whose outlets to refresh.
    def outlet_platform = software&.platform

    # Validation: adds an error when the software's platform expects no +html+
    # kind and the release has an +html+ asset.
    def download_only_platform_cannot_be_web_playable
      platform = WarpEngine::Platform.find(software&.platform)
      return if platform.nil? || platform.expected_kinds.include?("html")

      has_html = release_assets.reject(&:marked_for_destruction?).any? { |a| a.kind == "html" }
      if has_html
        errors.add(:base, "#{platform.label} releases cannot be web playable (download only)")
      end
    end

    ActiveSupport.run_load_hooks(:warp_engine_release, self)
  end
end
