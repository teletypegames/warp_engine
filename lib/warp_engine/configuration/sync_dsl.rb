module WarpEngine
  class Configuration
    # The <tt>sync do ... end</tt> block of WarpEngine::Configuration::DSL: the
    # event log, and the two directions in their own blocks
    # (WarpEngine::Configuration::SyncDirectionDSL).
    #
    #   sync do
    #     events :verbose
    #     outbound do
    #       enabled true
    #       allowed_platforms %w[c64]
    #       denied_kinds %w[win_x64 mac_universal]
    #     end
    #     inbound do
    #       enabled true
    #       allowed_platforms %w[c64 plus4]
    #     end
    #   end
    class SyncDSL
      # The settings that moved into the direction blocks in 5.0; naming one
      # here raises ArgumentError with where it went.
      MOVED = (%i[enabled software_switch timeout] + WarpEngine::Sync::Outbound.lists).freeze

      # Creates a DSL writing into the WarpEngine::Sync::Configuration +settings+.
      def initialize(settings)
        @settings = settings
      end

      # Sets the event log: +false+, +true+ or +:verbose+.
      def events(value = true) = @settings.events = value

      # Sets how many days the events are kept.
      def event_retention_days(value) = @settings.event_retention_days = value.to_i

      # Evaluates +block+ on the WarpEngine::Sync::Outbound settings.
      def outbound(&block) = SyncDirectionDSL.new(@settings.outbound).instance_eval(&block)

      # Evaluates +block+ on the WarpEngine::Sync::Inbound settings.
      def inbound(&block) = SyncDirectionDSL.new(@settings.inbound).instance_eval(&block)

      # Each MOVED name raises ArgumentError pointing at the outbound block.
      MOVED.each do |name|
        define_method(name) { |*| raise ArgumentError, "sync #{name} moved into the outbound block in WarpEngine 5.0: sync { outbound { #{name} ... } }" }
      end
    end

    # The <tt>outbound do ... end</tt> and <tt>inbound do ... end</tt> blocks of
    # WarpEngine::Configuration::SyncDSL; every method writes one setting of the
    # direction (WarpEngine::Sync::Outbound or WarpEngine::Sync::Inbound), and a
    # setting the direction does not have raises ArgumentError.
    class SyncDirectionDSL
      # Creates a DSL writing into the direction settings +settings+.
      def initialize(settings)
        @settings = settings
      end

      # Turns the direction on (or off with +false+).
      def enabled(value = true) = @settings.enabled = value

      # Sets the per-software switch (outbound): +false+, +:opt_out+ or +:opt_in+.
      def software_switch(value) = write(:software_switch, value)

      # Sets the seconds one request to a peer may take (outbound).
      def timeout(value) = write(:timeout, value.to_i)

      # Keeps a version published here from sync, or not (inbound).
      def protect_local(value = true) = write(:protect_local, value)

      # Sets who may pair (inbound): +:admin+ or +:anyone+.
      def pairing(value) = write(:pairing, value.to_s.to_sym)

      # Each list setting of either direction is a method taking the values,
      # as arguments or one Array.
      WarpEngine::Sync::Outbound.lists.each do |list|
        define_method(list) { |*values| write(list, values.flatten.map(&:to_s).uniq) }
      end

      private

      def write(name, value)
        raise ArgumentError, "sync #{@settings.class.label} has no #{name}" unless @settings.respond_to?(:"#{name}=")

        @settings.public_send(:"#{name}=", value)
      end
    end
  end
end
