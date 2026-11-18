module WarpEngine
  class Configuration
    # The <tt>sync do ... end</tt> block of WarpEngine::Configuration::DSL;
    # every method writes one WarpEngine::Sync::Configuration setting.
    #
    #   sync do
    #     enabled true
    #     software_switch :opt_out
    #     allowed_categories %w[game demo]
    #     denied_kinds %w[win_x64 mac_universal]
    #     events :verbose
    #   end
    class SyncDSL
      # Creates a DSL writing into the WarpEngine::Sync::Configuration +settings+.
      def initialize(settings)
        @settings = settings
      end

      # Turns sync on (or off with +false+).
      def enabled(value = true) = @settings.enabled = value

      # Sets the per-software switch: +false+, +:opt_out+ or +:opt_in+.
      def software_switch(value) = @settings.software_switch = value

      # Sets the event log: +false+, +true+ or +:verbose+.
      def events(value = true) = @settings.events = value

      # Sets how many days the events are kept.
      def event_retention_days(value) = @settings.event_retention_days = value.to_i

      # Sets the seconds one request to a sync server may take.
      def timeout(value) = @settings.timeout = value.to_i

      # Each WarpEngine::Sync::Configuration::LISTS name is a method taking
      # the list's values, as arguments or one Array.
      WarpEngine::Sync::Configuration::LISTS.each do |list|
        define_method(list) { |*values| @settings.public_send(:"#{list}=", values.flatten.map(&:to_s).uniq) }
      end
    end
  end
end
