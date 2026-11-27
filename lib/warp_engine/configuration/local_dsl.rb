module WarpEngine
  class Configuration
    # The <tt>local_providers do ... end</tt> block of
    # WarpEngine::Configuration::DSL; every method writes one
    # WarpEngine::Local::Configuration setting.
    #
    #   local_providers do
    #     enable
    #     engine_url "http://warp-engine-local:7470"
    #     scm_port 7471
    #   end
    class LocalDSL
      # Creates a DSL writing into the WarpEngine::Local::Configuration +settings+.
      def initialize(settings)
        @settings = settings
      end

      # Turns the local providers on (or off with +false+).
      def enable(value = true) = @settings.enabled = value

      # Sets the container runtime: +:docker+, +:null+ or a runtime object.
      def runtime(value) = @settings.runtime = value

      # Sets the Docker Engine socket inside this container.
      def socket(path) = @settings.socket = path.to_s

      # Sets the Docker Engine socket's path on the machine.
      def host_socket(path) = @settings.host_socket = path.to_s

      # Sets the docker network the providers join.
      def network(name) = @settings.network = name.to_s

      # Sets where the providers reach this engine.
      def engine_url(url) = @settings.engine_url = url.to_s

      # Sets the port the git server answers on, on 127.0.0.1.
      def scm_port(port) = @settings.scm_port = port.to_i

      # Publishes the CI's web UI on 127.0.0.1 at +port+.
      def ci_port(port) = @settings.ci_port = port&.to_i

      # Sets the start of the providers' container and volume names.
      def name_prefix(prefix) = @settings.name_prefix = prefix.to_s

      # Sets the organisation the repositories go to.
      def owner(name) = @settings.owner = name.to_s
    end
  end
end
