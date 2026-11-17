require "warp_engine/forge/gitea"

module WarpEngine
  # The forge seam: where the engine creates a new software's repository
  # (WarpEngine::ScaffoldService). The host picks it with
  # WarpEngine::Configuration#forge; without one, the engine creates no
  # repositories (Forge::Null).
  module Forge
    # A repository on the forge.
    #
    # [id]        the forge's id of the repository (what a CI activates)
    # [owner]     the owner or organisation
    # [name]      the repository name
    # [html_url]  the web page of the repository
    # [clone_url] the HTTPS clone URL
    # [ssh_url]   the SSH clone URL
    Repo = ::Data.define(:id, :owner, :name, :html_url, :clone_url, :ssh_url)

    # Raised when the forge cannot be reached or refuses a call.
    class Error < WarpEngine::Error; end

    # Raised when an operation needs a forge and none is configured.
    class NotConfigured < Error; end

    # The forge used when the host configured none: it creates nothing.
    class Null
      # Returns <tt>"none"</tt>.
      def name = "none"

      # Returns +false+.
      def configured? = false

      # Raises NotConfigured.
      def create_repo(**) = raise(NotConfigured, "no forge is configured (WarpEngine::Configuration#forge)")
    end

    class << self
      # Returns the forge adapter the configuration names, built again when
      # the settings change.
      def adapter
        settings = WarpEngine.config.forge_settings
        @adapter = nil unless @settings.equal?(settings)
        @settings = settings
        @adapter ||= build(settings)
      end

      # Forgets the built adapter (after a configuration change).
      def reset! = @adapter = nil

      private

      def build(settings)
        return Null.new if settings.nil?

        case settings[:type].to_s
        when "gitea" then Gitea.new(**settings.except(:type))
        else raise ConfigurationError, "unknown forge type #{settings[:type]}"
        end
      end
    end
  end

  # Returns the forge adapter (WarpEngine::Forge.adapter).
  def self.forge = Forge.adapter
end
