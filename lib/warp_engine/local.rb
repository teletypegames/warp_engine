require "warp_engine/local/configuration"

module WarpEngine
  # The services a local engine (profile +:local+) starts beside itself and
  # wires in: a git server and a CI, each a WarpEngine::Local::Component
  # (WarpEngine::Local::Components::Gitea, ...::Woodpecker) running in
  # containers on a WarpEngine::Local::Runtime (the Docker Engine on its
  # socket). Turned on by the host:
  #
  #   WarpEngine.configure do
  #     local_components do
  #       enable
  #       engine_url "http://warp-engine-local:7470"
  #       forge_port 7471
  #     end
  #   end
  #
  # While a component is ready, the engine's forge and CI seams
  # (WarpEngine.forge, WarpEngine.ci) answer with its adapter, so a scaffold
  # and the pipelines use it without a restart. The work is done by
  # WarpEngine::LocalComponentService and WarpEngine::LocalCiService in
  # WarpEngine::LocalOperation records.
  module Local
    # The label every container, network and volume of the components
    # carries; nothing without it is stopped or removed.
    LABEL = "org.teletypegames.warp-engine.local".freeze

    # A component step did not go through.
    class Error < WarpEngine::Error; end

    module_function

    # Returns the WarpEngine::Local::Configuration (WarpEngine::Configuration#local).
    def config = WarpEngine.config.local

    # Returns +true+ when the host turned the components on.
    def enabled? = config.enabled?

    # Returns +true+ when they are on and the runtime can start containers.
    def available? = enabled? && runtime.available?

    # Returns why the components cannot be used, or +nil+.
    def unavailable_reason
      return "local components are off (local_components { enable })" unless enabled?

      runtime.unavailable_reason
    end

    # Returns the WarpEngine::Local::Runtime the configuration names.
    def runtime
      configured = config.runtime
      case configured
      when :docker, "docker" then docker(config.socket)
      when :null, "null", nil then Runtime::Null.new
      else configured
      end
    end

    # Returns the WarpEngine::Local::Runtime::Docker on +socket+, made again
    # when the configured socket changed.
    def docker(socket)
      @docker = nil unless @docker_socket == socket
      @docker_socket = socket
      @docker ||= Runtime::Docker.new(socket: socket)
    end

    # Returns the WarpEngine::Local::Component of the ready component with
    # +role+, or +nil+.
    def ready(role)
      return nil unless enabled?

      LocalComponent.ready.find_by(role: role.to_s)&.component
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    # Returns the CI adapter of the ready +ci+ component built on +base+ (the
    # configured adapter), or +nil+.
    def ci_adapter(base) = ready(:ci)&.adapter(base)

    # Returns the forge adapter of the ready +forge+ component, or +nil+.
    def forge_adapter = ready(:forge)&.adapter
  end
end

require "warp_engine/local/runtime"
require "warp_engine/local/runtime/docker"
require "warp_engine/local/http"
require "warp_engine/local/component"
require "warp_engine/local/components"
require "warp_engine/local/components/gitea"
require "warp_engine/local/components/woodpecker"

WarpEngine::Local::Components.register(WarpEngine::Local::Components::Gitea)
WarpEngine::Local::Components.register(WarpEngine::Local::Components::Woodpecker)
