module WarpEngine
  module Local
    # What a provider asks a container runtime for: one container, its
    # +name+ (also its alias on the network), the +image+ with a fixed
    # version, its +env+ (a Hash), the named +volumes+ (volume name to path
    # inside), the +binds+ (<tt>host:container</tt> strings), the +ports+
    # published on 127.0.0.1 (host port to container port), more network
    # +aliases+, the +cmd+ (or +nil+) and the +user+ (or +nil+).
    ContainerSpec = ::Data.define(:name, :image, :env, :volumes, :binds, :ports, :aliases, :cmd, :user) do
      # Builds a spec with empty defaults for what is not given.
      def self.build(name:, image:, env: {}, volumes: {}, binds: [], ports: {}, aliases: [], cmd: nil, user: nil)
        new(name: name, image: image, env: env, volumes: volumes, binds: binds, ports: ports, aliases: aliases, cmd: cmd, user: user)
      end
    end

    # The base of the container runtimes the local providers run on
    # (WarpEngine::Local.runtime): WarpEngine::Local::Runtime::Docker (the
    # Docker Engine API on its socket) and WarpEngine::Local::Runtime::Null
    # (none). A runtime touches only containers carrying the LABEL.
    class Runtime
      # The runtime cannot do what was asked (no socket, an error answer).
      class Error < WarpEngine::Error; end

      # Returns +true+ when containers can be started.
      def available? = false

      # Returns why the runtime is not available, for a person, or +nil+.
      def unavailable_reason = "no container runtime"

      # Creates the network +name+ unless it exists.
      def ensure_network(_name) = raise(Error, unavailable_reason)

      # Pulls +image+ unless it is here.
      def pull(_image) = raise(Error, unavailable_reason)

      # Starts the container of +spec+ (a ContainerSpec) on +network+:
      # creates it, or starts it when it is stopped, or replaces it when its
      # image changed.
      def run(_spec, network:) = raise(Error, unavailable_reason)

      # Returns the state of the container +name+ (+running+, +exited+ …), or +nil+ when there is none.
      def state(_name) = nil

      # Stops the container +name+ when it runs.
      def stop(_name) = nil

      # Removes the container +name+.
      def remove(_name) = nil

      # Removes the volume +name+.
      def remove_volume(_name) = nil

      # Runs +cmd+ (an Array) in the container +name+ as +user+. Returns
      # <tt>[exit_code, output]</tt>.
      def exec(_name, _cmd, user: nil) = raise(Error, unavailable_reason)

      # A runtime with no containers: WarpEngine::Local is unavailable.
      class Null < Runtime
        # [reason] why there is no runtime
        def initialize(reason = "no container runtime is configured")
          super()
          @reason = reason
        end

        # Returns the reason given.
        def unavailable_reason = @reason
      end
    end
  end
end
