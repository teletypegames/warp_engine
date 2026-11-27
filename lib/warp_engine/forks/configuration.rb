module WarpEngine
  module Forks
    # The fork settings of the host, set in the <tt>forks</tt> block of
    # <tt>WarpEngine.configure</tt> (WarpEngine::Configuration::ForksDSL) and
    # read through WarpEngine::Forks.config. Announcing and accepting
    # announcements are both off by default.
    class Configuration
      # The values of #moderation: an announced fork waits for an
      # administrator, or is listed at once.
      MODERATIONS = %i[pending auto].freeze

      # [engine_url]           this engine's public base URL, the one forks name as their parent
      #                        (default +nil+: WarpEngine::Configuration#site_url)
      # [announce]             tell the parent engine when a fork of one of its softwares is
      #                        published here (default +false+; never from a non-public #engine_url)
      # [accept_announcements] take announcements of forks of our softwares at
      #                        <tt>POST /api/forks</tt> (default +false+)
      # [moderation]           one of MODERATIONS (default +:pending+)
      # [denied_engines]       host names whose announcements are dropped (default empty)
      # [announcements_per_hour] how many announcements one address may send in an hour (default 30)
      # [recheck_days]         WarpEngine::ForkRecheckJob verifies an announced fork again after this many days (default 7)
      # [timeout]              seconds one request to another engine or SCM may take (default 15)
      # [allow_private_engines] treat private and loopback addresses as public, for two engines
      #                        tried side by side on one machine (default +false+)
      attr_accessor :engine_url, :announce, :accept_announcements, :moderation, :denied_engines,
                    :announcements_per_hour, :recheck_days, :timeout, :allow_private_engines

      # Sets the defaults.
      def initialize
        @engine_url             = nil
        @announce               = false
        @accept_announcements   = false
        @moderation             = :pending
        @denied_engines         = []
        @announcements_per_hour = 30
        @recheck_days           = 7
        @timeout                = 15
        @allow_private_engines  = false
      end

      # Checks the settings. Raises ArgumentError for an unknown #moderation.
      # Returns the warnings worth logging.
      def validate!
        raise ArgumentError, "forks moderation must be one of #{MODERATIONS.inspect}" unless MODERATIONS.include?(moderation)

        warnings = []
        if (announce || accept_announcements) && WarpEngine::Forks.engine_url.blank?
          warnings << "forks: no engine_url (nor site_url) is set, so forks are neither announced nor verified"
        end
        warnings
      end
    end
  end
end
