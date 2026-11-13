module WarpEngine
  # The CI integration of the engine. Listing and activating repositories,
  # reading and triggering pipeline runs, provisioning secrets and serving
  # generated pipeline configs all go through one adapter, chosen with
  # <tt>WarpEngine.config.ci_adapter</tt> and returned by CI.adapter.
  #
  # Woodpecker (CI::Woodpecker::Adapter) is the default, CI::Gitlab::Adapter
  # ships too, CI::Null turns CI off, and any other object answering the
  # same methods can be set as the adapter.
  module CI
    # Base class of every error raised by a CI adapter or client.
    class Error < WarpEngine::Error; end

    # Raised when the CI server cannot be reached (refused connection, timeout, DNS failure).
    class ConnectionError < Error; end

    # Raised by CI::Null for every operation that needs a CI server.
    class NotConfigured < Error; end

    # Raised when the CI server answers with an error status or a body that is not JSON.
    class ApiError < Error
      # The HTTP status code (Integer or +nil+) and the raw response body of the failed request.
      attr_reader :status, :body

      # Creates the error.
      #
      # [message] the error message
      # [status]  the HTTP status code of the response, if any
      # [body]    the raw response body, if any
      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body   = body
      end
    end

    # A repository as the CI server knows it, built by the adapters.
    #
    # [id]     the CI server's id of the repository (Woodpecker repo id, GitLab project id)
    # [name]   the repository name
    # [owner]  the owner or namespace
    # [active] whether CI is enabled for it
    # [raw]    the provider's response Hash
    Repo = Struct.new(:id, :name, :owner, :active, :raw, keyword_init: true) do
      # Returns +true+ when CI is enabled for the repository.
      def active? = active ? true : false
      # Returns <tt>owner/name</tt>.
      def full_name = "#{owner}/#{name}"
    end

    # One pipeline run, built by the adapters.
    #
    # [number]     the run's number (Woodpecker) or pipeline id (GitLab)
    # [status]     the provider's status string, e.g. +success+
    # [branch]     the branch or ref built
    # [message]    the commit message, when the provider gives one
    # [created_at] the start time as a Time, or +nil+
    # [url]        the link to the run or commit on the forge
    # [raw]        the provider's response Hash
    Run = Struct.new(:number, :status, :branch, :message, :created_at, :url, :raw, keyword_init: true) do
      # Returns +true+ when the run's status is +success+.
      def success? = status.to_s == "success"

      # Returns the run as a camelCase Hash for the JSON API (without +raw+), +createdAt+ in ISO 8601 UTC.
      def as_json(*)
        {
          number:    number,
          status:    status,
          branch:    branch,
          message:   message,
          createdAt: created_at&.utc&.iso8601,
          url:       url
        }
      end
    end

    # The adapter used when CI is turned off (<tt>ci :none</tt>). It reports itself
    # as not configured, knows no platforms and serves no pipeline configs; every
    # operation that would talk to a CI server raises CI::NotConfigured.
    class Null
      # The message of the CI::NotConfigured errors raised by this adapter.
      MESSAGE = "no CI adapter is configured (WarpEngine.config.ci_adapter)".freeze

      # Returns <tt>"none"</tt>.
      def name = "none"
      # Returns +false+.
      def configured? = false
      # Returns an empty Hash: no platform has a pipeline.
      def platforms = {}
      # Returns +nil+: no kinds are built by CI.
      def built_kinds(_platform) = nil
      # Returns +nil+.
      def update_server = nil

      # Raises CI::NotConfigured.
      def repos                              = raise(NotConfigured, MESSAGE)
      # Raises CI::NotConfigured.
      def repo(_id)                          = raise(NotConfigured, MESSAGE)
      # Raises CI::NotConfigured.
      def activate_repo(_id)                 = raise(NotConfigured, MESSAGE)
      # Raises CI::NotConfigured.
      def deactivate_repo(_id)               = raise(NotConfigured, MESSAGE)
      # Raises CI::NotConfigured.
      def runs(_repo_id, page: 1)            = raise(NotConfigured, MESSAGE)
      # Raises CI::NotConfigured.
      def run(_repo_id, _number)             = raise(NotConfigured, MESSAGE)
      # Raises CI::NotConfigured.
      def trigger(_repo_id, branch: nil)     = raise(NotConfigured, MESSAGE)
      # Raises CI::NotConfigured.
      def secret_names(_repo_id)             = raise(NotConfigured, MESSAGE)
      # Raises CI::NotConfigured.
      def secret_set(_repo_id, name:, value:) = raise(NotConfigured, MESSAGE)
      # Raises CI::NotConfigured.
      def secret_delete(_repo_id, _name)     = raise(NotConfigured, MESSAGE)

      # Returns +false+: no config request is trusted.
      def verify_config_request(_request) = false
      # Returns +nil+: no config is a marker.
      def config_marker(_params) = nil
      # Returns +nil+: no pipeline is generated.
      def pipeline_config(platform:, name:, update_server:, options: {}) = nil
      # Returns an empty Hash.
      def config_response(platform:, config:, others: []) = {}
    end

    class << self
      # Returns the CI adapter in use, from <tt>WarpEngine.config.ci_adapter</tt>:
      # the memoized CI::Woodpecker::Adapter for +nil+ or +:woodpecker+, the
      # CI::Gitlab::Adapter for +:gitlab+, CI::Null for +:none+ or +:null+, and
      # any other value (a host-supplied adapter object) as it is.
      def adapter
        configured = WarpEngine.config.ci_adapter

        case configured
        when nil, :woodpecker, "woodpecker" then woodpecker_adapter
        when :gitlab, "gitlab"              then gitlab_adapter
        when :none, "none", :null           then null_adapter
        else configured
        end
      end

      # Returns +true+ when the adapter in use is a CI::Woodpecker::Adapter.
      def woodpecker? = adapter.is_a?(Woodpecker::Adapter)
      # Returns +true+ when the adapter in use is a CI::Gitlab::Adapter.
      def gitlab?     = adapter.is_a?(Gitlab::Adapter)

      # Returns the memoized CI::Woodpecker::Adapter, configured from ENV.
      def woodpecker_adapter
        @woodpecker_adapter ||= Woodpecker::Adapter.new
      end

      # Returns the memoized CI::Gitlab::Adapter, configured from ENV.
      def gitlab_adapter
        @gitlab_adapter ||= Gitlab::Adapter.new
      end

      # Returns the memoized CI::Null adapter.
      def null_adapter
        @null_adapter ||= Null.new
      end

      # Forgets the memoized adapters, so the next call builds them again. Returns +nil+.
      def reset!
        @woodpecker_adapter = nil
        @gitlab_adapter = nil
        @null_adapter = nil
      end
    end
  end
end

require "warp_engine/ci/woodpecker"
require "warp_engine/ci/gitlab"
