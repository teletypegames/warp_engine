module WarpEngine
  module Local
    # The settings of the local components (WarpEngine::Local), set in the
    # <tt>local_components</tt> block of <tt>WarpEngine.configure</tt>
    # (WarpEngine::Configuration::LocalDSL) and read through
    # WarpEngine::Local.config. Off by default: a server host never starts
    # containers.
    class Configuration
      # [enabled]     the components may be used (default +false+)
      # [runtime]     +:docker+ (default), +:null+, or an object answering the
      #               WarpEngine::Local::Runtime methods
      # [socket]      the Docker Engine socket inside this container (default <tt>/var/run/docker.sock</tt>)
      # [host_socket] the same socket's path on the machine, bound into the CI agent (default <tt>/var/run/docker.sock</tt>)
      # [network]     the docker network the components and this engine share (default +warp-local+)
      # [engine_url]  where the components reach this engine on that network (e.g. <tt>http://warp-engine-local:7470</tt>)
      # [forge_port]  the port on 127.0.0.1 the git server answers on (default 7471)
      # [owner]       the organisation the repositories go to (default +games+)
      # [ci_port]     the port on 127.0.0.1 the CI's web UI answers on, or +nil+
      #               (the default: the CI is reached only on the network)
      # [name_prefix] the start of the components' container and volume names
      #               (default +warp-local+: <tt>warp-local-gitea</tt> …), so two
      #               engines on one machine keep theirs apart
      attr_accessor :enabled, :runtime, :socket, :host_socket, :network, :engine_url, :forge_port, :owner, :name_prefix, :ci_port

      # Sets the defaults listed above.
      def initialize
        @enabled = false
        @runtime = :docker
        @socket = "/var/run/docker.sock"
        @host_socket = "/var/run/docker.sock"
        @network = "warp-local"
        @engine_url = nil
        @forge_port = 7471
        @owner = "games"
        @name_prefix = "warp-local"
      end

      # Returns the container or volume name +suffix+ with the #name_prefix.
      def name(suffix) = "#{name_prefix}-#{suffix}"

      # Whether the components may be used.
      def enabled? = enabled == true

      # Returns the host name of #engine_url, the name the components call this engine by.
      def engine_host = URI.parse(engine_url.to_s).host
    end
  end
end
