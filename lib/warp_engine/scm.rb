require "warp_engine/scm/gitea"

module WarpEngine
  # The SCM seam: where the engine creates a new software's repository
  # (WarpEngine::ScaffoldService). The host picks it with
  # WarpEngine::Configuration#scm; without one, the engine creates no
  # repositories (Scm::Null).
  module Scm
    # A repository on the SCM.
    #
    # [id]        the SCM's id of the repository (what a CI activates)
    # [owner]     the owner or organisation
    # [name]      the repository name
    # [html_url]  the web page of the repository
    # [clone_url] the HTTPS clone URL
    # [ssh_url]   the SSH clone URL
    Repo = ::Data.define(:id, :owner, :name, :html_url, :clone_url, :ssh_url)

    # Raised when the SCM cannot be reached or refuses a call.
    class Error < WarpEngine::Error; end

    # Raised when an operation needs an SCM and none is configured.
    class NotConfigured < Error; end

    # The SCM used when the host configured none: it creates nothing.
    class Null
      # Returns <tt>"none"</tt>.
      def name = "none"

      # Returns +false+.
      def configured? = false

      # Returns +nil+: there is no SCM to ask.
      def find_repo(_name) = nil

      # Raises NotConfigured.
      def create_repo(**) = raise(NotConfigured, "no SCM is configured (WarpEngine::Configuration#scm)")

      # Returns +nil+: there is no SCM to ask.
      def open_pull_request(**) = nil

      # Raises NotConfigured.
      def upsert_comment(**) = raise(NotConfigured, "no SCM is configured (WarpEngine::Configuration#scm)")
    end

    class << self
      # Returns the SCM adapter: the ready local SCM provider's
      # (WarpEngine::Local.scm_adapter), else the one the configuration
      # names, built again when the settings change.
      def adapter
        local = WarpEngine::Local.scm_adapter
        return local if local

        settings = WarpEngine.config.scm_settings
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
        else raise ConfigurationError, "unknown scm type #{settings[:type]}"
        end
      end
    end
  end

  # Returns the SCM adapter (WarpEngine::Scm.adapter).
  def self.scm = Scm.adapter
end
