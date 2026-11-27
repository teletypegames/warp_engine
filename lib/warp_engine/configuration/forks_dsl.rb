module WarpEngine
  class Configuration
    # The <tt>forks do ... end</tt> block of WarpEngine::Configuration::DSL;
    # every method writes one setting of WarpEngine::Forks::Configuration.
    #
    #   forks do
    #     engine_url "https://games.example"
    #     announce true
    #     accept_announcements true
    #     moderation :pending
    #     denied_engines %w[spam.example]
    #   end
    class ForksDSL
      # Creates a DSL writing into the WarpEngine::Forks::Configuration +settings+.
      def initialize(settings)
        @settings = settings
      end

      # Sets this engine's public base URL.
      def engine_url(value) = @settings.engine_url = value.to_s

      # Turns announcing our forks to their parents on (or off with +false+).
      def announce(value = true) = @settings.announce = value

      # Turns taking announcements on (or off with +false+).
      def accept_announcements(value = true) = @settings.accept_announcements = value

      # Sets the moderation of announced forks: +:pending+ or +:auto+.
      def moderation(value) = @settings.moderation = value.to_s.to_sym

      # Sets the host names whose announcements are dropped, as arguments or one Array.
      def denied_engines(*names) = @settings.denied_engines = names.flatten.map(&:to_s).uniq

      # Sets how many announcements one address may send in an hour.
      def announcements_per_hour(value) = @settings.announcements_per_hour = value.to_i

      # Sets after how many days an announced fork is verified again.
      def recheck_days(value) = @settings.recheck_days = value.to_i

      # Treats private and loopback addresses as public (or not with +false+).
      def allow_private_engines(value = true) = @settings.allow_private_engines = value

      # Sets the seconds one request to another engine or SCM may take.
      def timeout(value) = @settings.timeout = value.to_i
    end
  end
end
