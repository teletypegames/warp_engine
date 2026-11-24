module WarpEngine
  # One version of a software (table +releases+), unique per software, on the
  # +channel+ its version says (WarpEngine::Channels: +stable+, +beta+, +dev+;
  # set on every save, never by hand). Has
  # many kept +downloads+ and +release_assets+ (editable as nested
  # attributes). A release of a download-only platform may not have an +html+
  # asset. Its +origin+ says where it was published from: +ci+ (this engine's
  # CI, or by hand) or +sync+ (a WarpEngine::SyncPeer pushed it, +sync_peer+).
  # Soft-deletable; saving or deleting one refreshes the outlets (shelves) of the
  # software's platform.
  class Release < ApplicationRecord
    self.table_name = "releases"

    # Where a release can come from: this engine's CI (or by hand), or a sync peer.
    ORIGINS = %w[ci sync].freeze

    include SoftDeletable
    include OutletRefreshing
    include RemovalNotifying

    belongs_to :software
    belongs_to :runtime_version, optional: true
    belongs_to :sync_peer, optional: true, inverse_of: :releases
    has_many :sync_events, -> { order(created_at: :desc, id: :desc) }, inverse_of: :release
    has_many :downloads, -> { kept }
    has_many :release_assets, -> { kept }

    accepts_nested_attributes_for :release_assets, allow_destroy: true

    validates :version, presence: true
    validates :version, uniqueness: { scope: :software_id }

    validates :channel, inclusion: { in: WarpEngine::Channels::ALL }
    validates :origin, inclusion: { in: ORIGINS }

    validate :download_only_platform_cannot_be_web_playable

    before_validation { self.channel = WarpEngine::Channels.for(version) }

    # Returns +true+ when a sync peer pushed this release.
    def synced? = origin == "sync"

    scope :listed, -> { where.not(channel: WarpEngine::Channels::DEV) }
    scope :in_channels, ->(channels) { where(channel: Array(channels)) }

    # Returns the newest of +releases+ (by creation time, then id) on a channel
    # offered to a caller asking for +channel+ (WarpEngine::Channels.offered:
    # +stable+, or +stable+ and +beta+ for +beta+); +nil+ when there is none.
    # A development build is never the latest.
    def self.latest(releases, channel: WarpEngine::Channels::STABLE)
      offered = WarpEngine::Channels.offered(channel)
      releases.select { |r| offered.include?(r.channel) }.max_by { |r| [ r.created_at || Time.at(0), r.id ] }
    end

    # Returns +true+ for a development build (WarpEngine::Channels::DEV).
    def dev? = channel == WarpEngine::Channels::DEV

    # Returns the branch a development build was made of
    # (WarpEngine::Channels.branch_of), or +nil+.
    def branch = WarpEngine::Channels.branch_of(version)

    # Returns the software's platform, whose outlets to refresh.
    def outlet_platform = software&.platform

    # Validation: adds an error when the software's platform expects no +html+
    # kind and the release has an +html+ asset.
    def download_only_platform_cannot_be_web_playable
      platform = WarpEngine::Platform.for(software)
      return if platform.nil? || platform.expected_kinds.include?("html")

      has_html = release_assets.reject(&:marked_for_destruction?).any? { |a| a.kind == "html" }
      if has_html
        errors.add(:base, "#{platform.label} releases cannot be web playable (download only)")
      end
    end

    ActiveSupport.run_load_hooks(:warp_engine_release, self)
  end
end
