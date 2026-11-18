module WarpEngine
  module Sync
    # The sync settings of the host, set in the <tt>sync</tt> block of
    # <tt>WarpEngine.configure</tt> (WarpEngine::Configuration::SyncDSL) and read
    # through WarpEngine::Sync.config: the two directions, #outbound (what this
    # engine pushes to its peers) and #inbound (what it accepts from them), both
    # off by default, and the event log.
    class Configuration
      # The values of #events: no events, the pushes and the incoming
      # publishes, and those plus the releases a filter held back.
      EVENT_LEVELS = [ false, true, :verbose ].freeze

      # [events]               one of EVENT_LEVELS (default +true+)
      # [event_retention_days] WarpEngine::SyncEventPruneJob removes older events (default 90)
      attr_accessor :events, :event_retention_days

      # The WarpEngine::Sync::Outbound and WarpEngine::Sync::Inbound settings.
      attr_accessor :outbound, :inbound

      # Sets the defaults.
      def initialize
        @events               = true
        @event_retention_days = 90
        @outbound             = Outbound.new
        @inbound              = Inbound.new
      end

      # Whether WarpEngine::SyncEvent records are written.
      def events? = events == true || events == :verbose

      # Whether the releases a filter held back are written as +skipped+ events too.
      def verbose_events? = events == :verbose

      # Checks the settings. Raises ArgumentError for an unknown #events value
      # or a list entry no direction may name. Returns the warnings worth logging.
      def validate!
        raise ArgumentError, "sync events must be one of #{EVENT_LEVELS.inspect}" unless EVENT_LEVELS.include?(events)

        outbound.validate! + inbound.validate! + Transports.validate!
      end
    end
  end
end
