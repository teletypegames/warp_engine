module WarpEngine
  # One line of the sync log (table +sync_events+): a push to a
  # WarpEngine::SyncServer (+outbound+) or a release another engine pushed
  # here (+inbound+, with the +token_prefix+ it came with). It names the
  # release by +software_name+, +platform+ and +version+ (and +release_id+
  # while it exists), and records the +status+, the +step+ it stopped at,
  # the other side's +http_status+ and +message+, the files and +bytes+
  # sent, the +duration_ms+ and the +attempt+. Written only while
  # WarpEngine::Sync::Configuration#events? holds.
  class SyncEvent < ApplicationRecord
    self.table_name = "sync_events"

    # The directions.
    DIRECTIONS = %w[outbound inbound].freeze

    # The statuses, in the order a push passes them.
    STATUSES = %w[queued running succeeded failed skipped].freeze

    belongs_to :sync_server, optional: true, inverse_of: :sync_events

    enum :direction, DIRECTIONS.index_by(&:itself)
    enum :status, STATUSES.index_by(&:itself)

    validates :direction, :status, presence: true

    scope :recent, -> { order(created_at: :desc, id: :desc) }

    # Creates an event from +attributes+ when the events are on; returns it,
    # or +nil+ when they are off.
    def self.log(**attributes)
      return nil unless WarpEngine::Sync.config.events?

      create!(attributes)
    end

    # Fills the release columns from +release+ into +attributes+ and returns them.
    def self.release_attributes(release)
      { release_id: release.id, software_name: release.software&.name, platform: release.software&.platform,
        version: release.version }
    end

    # Allows the server association in Ransack searches.
    def self.ransackable_associations(auth_object = nil) = %w[sync_server]

    # Allows the plain columns in Ransack searches.
    def self.ransackable_attributes(auth_object = nil)
      %w[id sync_server_id direction status software_name platform version http_status created_at]
    end

    ActiveSupport.run_load_hooks(:warp_engine_sync_event, self)
  end
end
