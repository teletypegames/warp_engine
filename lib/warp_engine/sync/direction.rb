module WarpEngine
  module Sync
    # The settings of one sync direction, the shared part of
    # WarpEngine::Sync::Outbound and WarpEngine::Sync::Inbound: whether it is
    # on, and the lists that decide which releases pass (WarpEngine::Sync::Filter).
    class Direction
      # The filter lists both directions have, each an Array of strings (empty:
      # no filter on that axis). The +softwares+ lists take software names with
      # <tt>*</tt> as a wildcard; the others exact keys.
      LISTS = %i[allowed_softwares denied_softwares allowed_categories denied_categories
                 allowed_platforms denied_platforms allowed_statuses denied_statuses allowed_channels].freeze

      # [enabled]            the direction is on (default +false+)
      # [allowed_softwares]  software names (<tt>*</tt> wildcards) that may pass
      # [denied_softwares]   software names (<tt>*</tt> wildcards) that never pass
      # [allowed_categories] category keys that may pass
      # [denied_categories]  category keys that never pass
      # [allowed_platforms]  platform names that may pass
      # [denied_platforms]   platform names that never pass
      # [allowed_statuses]   status keys that may pass
      # [denied_statuses]    status keys that never pass
      # [allowed_channels]   the release channels that pass (default <tt>%w[stable]</tt>)
      attr_accessor :enabled, *LISTS

      # Sets the defaults listed above.
      def initialize
        @enabled = false
        self.class.lists.each { |list| instance_variable_set(:"@#{list}", []) }
        @allowed_channels = [ WarpEngine::Channels::STABLE ]
      end

      # Returns the list settings of the class: LISTS, plus a subclass's own.
      def self.lists = LISTS

      # Returns the name of the direction in messages (+outbound+, +inbound+).
      def self.label = name.demodulize.downcase

      # Whether the direction is on.
      def enabled? = enabled == true

      # Returns +false+: only WarpEngine::Sync::Outbound has a per-software switch.
      def software_switch = false

      # Returns a copy with +overrides+ (setting name to value) applied.
      def with(**overrides)
        dup.tap do |copy|
          self.class.lists.each { |list| copy.public_send(:"#{list}=", Array(public_send(list)).dup) }
          overrides.each { |name, value| copy.public_send(:"#{name}=", value) }
        end
      end

      # Checks the lists. Raises ArgumentError for a platform or channel no
      # list may name. Returns the warnings worth logging (none here).
      def validate!
        check_keys(%i[allowed_platforms denied_platforms], WarpEngine::Platform.names, "platform")
        check_keys(%i[allowed_channels], WarpEngine::Channels::ALL, "channel")
        []
      end

      private

      def check_keys(lists, known, what)
        lists.each do |list|
          unknown = Array(public_send(list)).map(&:to_s) - known
          next if unknown.empty?

          raise ArgumentError, "sync #{self.class.label} #{list}: unknown #{what} #{unknown.join(', ')} (#{known.join(', ')})"
        end
      end
    end

    # The <tt>outbound</tt> settings: whether this engine pushes its releases
    # to the sync peers, and which. Besides the lists of WarpEngine::Sync::Direction:
    #
    # [software_switch] one of SOFTWARE_SWITCHES (default +false+)
    # [allowed_kinds]   asset kinds whose files go (required kinds always do)
    # [denied_kinds]    asset kinds whose files stay (required kinds still go)
    # [timeout]         seconds one request to a peer may take (default 120)
    class Outbound < Direction
      # The values of #software_switch: no switch, every software unless
      # switched off, no software unless switched on.
      SOFTWARE_SWITCHES = [ false, :opt_out, :opt_in ].freeze

      # The kind lists, which choose a release's files rather than the release.
      KIND_LISTS = %i[allowed_kinds denied_kinds].freeze

      # The per-software switch, the kind lists and the request timeout (see above).
      attr_accessor :software_switch, :timeout, *KIND_LISTS

      # Sets the defaults.
      def initialize
        super
        @software_switch = false
        @timeout = 120
      end

      # Returns the list settings: Direction::LISTS and KIND_LISTS.
      def self.lists = Direction::LISTS + KIND_LISTS

      # Whether the software admin shows the per-software switch.
      def software_switch? = software_switch.present?

      # Returns a copy that holds nothing back: no switch, no lists, every
      # kind, only the +channels+ (default every channel).
      def permissive(channels: WarpEngine::Channels::ALL)
        with(software_switch: false, **(self.class.lists - [ :allowed_channels ]).to_h { |list| [ list, [] ] },
             allowed_channels: Array(channels).map(&:to_s))
      end

      # Checks the settings (see Direction#validate!) and the switch and kind
      # lists. Raises ArgumentError for an unknown value. Returns the warnings:
      # the kinds a list leaves out although a platform requires them, which
      # still go.
      def validate!
        raise ArgumentError, "sync outbound software_switch must be one of #{SOFTWARE_SWITCHES.inspect}" unless SOFTWARE_SWITCHES.include?(software_switch)

        super
        check_keys(KIND_LISTS, WarpEngine::AssetKinds.names, "asset kind")
        required_kind_warnings
      end

      private

      def required_kind_warnings
        return [] if allowed_kinds.blank? && denied_kinds.blank?

        WarpEngine::Platform.all.flat_map do |platform|
          platform.required_kinds.reject { |kind| Filter.kind_allowed?(kind, self) }.map do |kind|
            "sync: the #{platform.name} platform requires #{kind}, so it goes although the kind lists leave it out"
          end
        end
      end
    end

    # The <tt>inbound</tt> settings: whether other engines may push their
    # releases here (with a token of a WarpEngine::SyncPeer), and which.
    # Besides the lists of WarpEngine::Sync::Direction:
    #
    # [protect_local] a version this engine published itself (origin +ci+) is
    #                 not overwritten by sync (default +true+)
    class Inbound < Direction
      # Whether a version published here by the CI is kept from sync (see above).
      attr_accessor :protect_local

      # Sets the defaults.
      def initialize
        super
        @protect_local = true
      end

      # Whether #protect_local is on.
      def protect_local? = protect_local != false
    end
  end
end
