module WarpEngine
  # Decides who may see a title and who may download it. The policy is an
  # object with three methods (+visible_software_scope+, +access_for+,
  # +authorize_download+), set with <tt>access_policy</tt> in the configuration;
  # the default is AccessPolicy::Open.
  module AccessPolicy
    # The default policy: every kept software is listed, nothing is gated and
    # every download is allowed.
    class Open
      # Returns the scope of the titles the catalog lists for +subject+: every
      # kept WarpEngine::Software.
      def visible_software_scope(subject: nil)
        WarpEngine::Software.kept
      end

      # Returns WarpEngine::Access::OPEN for any +software+ and +subject+.
      def access_for(software:, subject: nil)
        Access::OPEN
      end

      # Allows every download: returns WarpEngine::Access::Grant::OPEN. A policy
      # returning +nil+ here refuses the download.
      def authorize_download(asset: nil, subject: nil, request: nil)
        Access::Grant::OPEN
      end
    end

    class << self
      # Returns the configured policy object; +nil+, +:open+ or <tt>"open"</tt>
      # give the shared Open instance.
      def current
        configured = WarpEngine.config.access_policy

        case configured
        when nil, :open, "open" then open_policy
        else configured
        end
      end

      # Returns +true+ when the current policy is Open.
      def open? = current.is_a?(Open)

      # Returns the memoized Open instance.
      def open_policy
        @open_policy ||= Open.new
      end

      # Drops the memoized Open instance.
      def reset!
        @open_policy = nil
      end
    end
  end
end
