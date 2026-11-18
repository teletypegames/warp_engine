module WarpEngine
  module Sync
    # The sync settings of the host, set in the <tt>sync</tt> block of
    # <tt>WarpEngine.configure</tt> (WarpEngine::Configuration::SyncDSL) and read
    # through WarpEngine::Sync.config. Every setting has a working default;
    # sync is off until +enabled+ is set.
    class Configuration
      # The values of #software_switch: no switch, every software unless
      # switched off, no software unless switched on.
      SOFTWARE_SWITCHES = [ false, :opt_out, :opt_in ].freeze

      # The values of #events: no events, the pushes and the incoming
      # publishes, and those plus the releases a filter held back.
      EVENT_LEVELS = [ false, true, :verbose ].freeze

      # The filter lists, each an Array of strings (empty: no filter on that
      # axis). The +softwares+ lists take software names with <tt>*</tt> as a
      # wildcard; the others exact keys.
      LISTS = %i[allowed_softwares denied_softwares allowed_categories denied_categories
                 allowed_platforms denied_platforms allowed_statuses denied_statuses
                 allowed_kinds denied_kinds allowed_channels].freeze

      # The settings:
      #
      # [enabled]              push the releases to the sync servers at all (default +false+)
      # [software_switch]      one of SOFTWARE_SWITCHES (default +false+)
      # [allowed_softwares]    software names (<tt>*</tt> wildcards) that may go
      # [denied_softwares]     software names (<tt>*</tt> wildcards) that never go
      # [allowed_categories]   category keys that may go
      # [denied_categories]    category keys that never go
      # [allowed_platforms]    platform names that may go
      # [denied_platforms]     platform names that never go
      # [allowed_statuses]     status keys that may go
      # [denied_statuses]      status keys that never go
      # [allowed_kinds]        asset kinds whose files go (required kinds always do)
      # [denied_kinds]         asset kinds whose files stay (required kinds still go)
      # [allowed_channels]     the release channels that go (default <tt>%w[stable]</tt>)
      # [events]               one of EVENT_LEVELS (default +true+)
      # [event_retention_days] WarpEngine::SyncEventPruneJob removes older events (default 90)
      # [timeout]              seconds one request to a sync server may take (default 120)
      attr_accessor :enabled, :software_switch, :events, :event_retention_days, :timeout, *LISTS

      # Sets the defaults listed above.
      def initialize
        @enabled              = false
        @software_switch      = false
        @events               = true
        @event_retention_days = 90
        @timeout              = 120
        LISTS.each { |list| instance_variable_set(:"@#{list}", []) }
        @allowed_channels = [ WarpEngine::Channels::STABLE ]
      end

      # Returns a copy with +overrides+ (setting name to value) applied.
      def with(**overrides)
        dup.tap do |copy|
          LISTS.each { |list| copy.public_send(:"#{list}=", Array(public_send(list)).dup) }
          overrides.each { |name, value| copy.public_send(:"#{name}=", value) }
        end
      end

      # Returns a copy that holds nothing back: no switch, no lists, every
      # kind, only the +channels+ (default every channel).
      def permissive(channels: WarpEngine::Channels::ALL)
        with(software_switch: false, **(LISTS - [ :allowed_channels ]).to_h { |list| [ list, [] ] },
             allowed_channels: Array(channels).map(&:to_s))
      end

      # Whether sync is on.
      def enabled? = enabled == true

      # Whether WarpEngine::SyncEvent records are written.
      def events? = events == true || events == :verbose

      # Whether the releases a filter held back are written as +skipped+ events too.
      def verbose_events? = events == :verbose

      # Whether the software admin shows the per-software switch.
      def software_switch? = software_switch.present?

      # Checks the settings. Raises ArgumentError for an unknown
      # #software_switch or #events value, or a platform, channel or asset kind
      # no list may name. Returns the warnings worth logging: the kinds a list
      # leaves out although a platform requires them, which still go.
      def validate!
        raise ArgumentError, "sync software_switch must be one of #{SOFTWARE_SWITCHES.inspect}" unless SOFTWARE_SWITCHES.include?(software_switch)
        raise ArgumentError, "sync events must be one of #{EVENT_LEVELS.inspect}" unless EVENT_LEVELS.include?(events)

        check_keys(%i[allowed_platforms denied_platforms], WarpEngine::Platform.names, "platform")
        check_keys(%i[allowed_channels], WarpEngine::Channels::ALL, "channel")
        check_keys(%i[allowed_kinds denied_kinds], WarpEngine::AssetKinds.names, "asset kind")
        required_kind_warnings
      end

      private

      def check_keys(lists, known, what)
        lists.each do |list|
          unknown = Array(public_send(list)).map(&:to_s) - known
          raise ArgumentError, "sync #{list}: unknown #{what} #{unknown.join(', ')} (#{known.join(', ')})" if unknown.any?
        end
      end

      def required_kind_warnings
        return [] if allowed_kinds.blank? && denied_kinds.blank?

        WarpEngine::Platform.all.flat_map do |platform|
          platform.required_kinds.reject { |kind| Filter.kind_allowed?(kind, self) }.map do |kind|
            "sync: the #{platform.name} platform requires #{kind}, so it goes although the kind lists leave it out"
          end
        end
      end
    end
  end
end
