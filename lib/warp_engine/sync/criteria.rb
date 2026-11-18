module WarpEngine
  module Sync
    # What a sync run sends (WarpEngine::SyncService#plan and #run): the
    # newest release of each software or every release (+mode+), whether the
    # configured filters apply (+filtered+; without them every software and
    # every kind goes), the +channels+ that go, and narrowings on top: software
    # names (<tt>*</tt> wildcards), platforms, categories and statuses, each
    # ignored when empty; and whether a release the server already has with
    # every kind it would get is left out (+skip_existing+, asked of the
    # server when the push runs). Travels to WarpEngine::SyncPushJob as #to_h.
    Criteria = ::Data.define(:mode, :filtered, :channels, :softwares, :platforms, :categories, :statuses,
                             :skip_existing) do
      # The modes: the newest allowed release of each software, or every one.
      const_set(:MODES, %w[latest all].freeze)

      # The narrowing lists.
      const_set(:NARROWINGS, %i[softwares platforms categories statuses].freeze)

      # Builds Criteria from loose values: +mode+ <tt>"latest"</tt> unless
      # <tt>"all"</tt>, +filtered+ and +skip_existing+ true unless false or
      # <tt>"0"</tt>, +channels+
      # by default WarpEngine::Sync::Configuration#allowed_channels, the lists
      # from Arrays or comma or space separated strings. Raises ArgumentError
      # for an unknown channel.
      def self.build(mode: "latest", filtered: true, channels: nil, softwares: nil, platforms: nil, categories: nil,
                     statuses: nil, skip_existing: true, config: Sync.config)
        chosen = list(channels).presence || Array(config.allowed_channels).map(&:to_s)
        unknown = chosen - WarpEngine::Channels::ALL
        raise ArgumentError, "unknown channel #{unknown.join(', ')}" if unknown.any?

        new(mode: mode.to_s == "all" ? "all" : "latest", filtered: truthy?(filtered), skip_existing: truthy?(skip_existing),
            channels: chosen, softwares: list(softwares), platforms: list(platforms),
            categories: list(categories), statuses: list(statuses))
      end

      # Returns +false+ for +false+, <tt>"false"</tt>, <tt>"0"</tt> and 0,
      # +true+ for anything else.
      def self.truthy?(value) = ![ false, "false", "0", 0 ].include?(value)

      # Builds Criteria from the Hash #to_h made (string or symbol keys).
      def self.from_h(hash) = build(**hash.to_h.symbolize_keys.slice(*members))

      # Splits +value+ (an Array, or a string separated by commas or spaces)
      # into a list of distinct, non-blank strings.
      def self.list(value)
        items = value.is_a?(String) ? value.split(/[\s,]+/) : Array(value)
        items.map { |item| item.to_s.strip }.compact_blank.uniq
      end

      # Whether every allowed release goes, not only the newest.
      def all? = mode == "all"

      # Returns the WarpEngine::Sync::Filter of the run: the configured one
      # with #channels when #filtered, else one that holds nothing back
      # but the channel.
      def filter(config = Sync.config)
        Filter.new(filtered ? config.with(allowed_channels: channels) : config.permissive(channels: channels))
      end

      # Returns why the narrowings leave +software+ out, or +nil+ when they
      # do not.
      def reason(software)
        if softwares.any? && !Filter.name_matches?(software.name, softwares)
          return "#{software.name} is not among the chosen softwares"
        end

        { platforms: software.platform, categories: software.category, statuses: software.status }.each do |axis, value|
          chosen = public_send(axis)
          return "#{value.presence || 'no value'} is not among the chosen #{axis}" if chosen.any? && !chosen.include?(value.to_s)
        end
        nil
      end

      # Returns a one-line description, e.g. <tt>newest, configured filters, stable</tt>.
      def summary
        parts = [ all? ? "every release" : "newest release", filtered ? "configured filters" : "no configured filters",
                  channels.join("+"), skip_existing ? "skipping what the server has" : "sending again what the server has" ]
        self.class::NARROWINGS.each { |axis| parts << "#{axis}: #{public_send(axis).join(', ')}" if public_send(axis).any? }
        parts.join(", ")
      end
    end
  end
end
