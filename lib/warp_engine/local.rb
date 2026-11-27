require "warp_engine/local/configuration"

module WarpEngine
  # The services a local engine (profile +:local+) starts beside itself and
  # wires in: a git server and a CI, each a WarpEngine::Local::Provider
  # (WarpEngine::Local::Providers::Gitea, ...::Woodpecker) running in
  # containers on a WarpEngine::Local::Runtime (the Docker Engine on its
  # socket). Turned on by the host:
  #
  #   WarpEngine.configure do
  #     local_providers do
  #       enable
  #       engine_url "http://warp-engine-local:7470"
  #       scm_port 7471
  #     end
  #   end
  #
  # While a provider is ready, the engine's SCM and CI seams
  # (WarpEngine.scm, WarpEngine.ci) answer with its adapter, so a scaffold
  # and the pipelines use it without a restart. The work is done by
  # WarpEngine::LocalProviderService and WarpEngine::LocalCiService in
  # WarpEngine::LocalTask records.
  module Local
    # The label every container, network and volume of the providers
    # carries; nothing without it is stopped or removed.
    LABEL = "org.teletypegames.warp-engine.local".freeze

    # A provider step did not go through.
    class Error < WarpEngine::Error; end

    module_function

    # Returns the WarpEngine::Local::Configuration (WarpEngine::Configuration#local).
    def config = WarpEngine.config.local

    # Returns +true+ when the host turned the providers on.
    def enabled? = config.enabled?

    # Returns +true+ when they are on and the runtime can start containers.
    def available? = enabled? && runtime.available?

    # Returns why the providers cannot be used, or +nil+.
    def unavailable_reason
      return "local providers are off (local_providers { enable })" unless enabled?

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

    # Returns the WarpEngine::Local::Provider of the ready provider with
    # +role+, or +nil+.
    def ready(role)
      return nil unless enabled?

      LocalProvider.ready.find_by(role: role.to_s)&.provider
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    # Returns the CI adapter of the ready +ci+ provider built on +base+ (the
    # configured adapter), or +nil+.
    def ci_adapter(base) = ready(:ci)&.adapter(base)

    # Returns the SCM adapter of the ready +scm+ provider, or +nil+.
    def scm_adapter = ready(:scm)&.adapter
  end
end

require "warp_engine/local/runtime"
require "warp_engine/local/runtime/docker"
require "warp_engine/local/http"
require "warp_engine/local/provider"
require "warp_engine/local/providers"
require "warp_engine/local/providers/gitea"
require "warp_engine/local/providers/woodpecker"

WarpEngine::Local::Providers.register(WarpEngine::Local::Providers::Gitea)
WarpEngine::Local::Providers.register(WarpEngine::Local::Providers::Woodpecker)
