module WarpEngine

  module CI
    class Error < StandardError; end

    class ConnectionError < Error; end

    class NotConfigured < Error; end

    class ApiError < Error
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body   = body
      end
    end

    Repo = Struct.new(:id, :name, :owner, :active, :raw, keyword_init: true) do
      def active? = active ? true : false
      def full_name = "#{owner}/#{name}"
    end

    Run = Struct.new(:number, :status, :branch, :message, :created_at, :url, :raw, keyword_init: true) do
      def success? = status.to_s == "success"

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

    class Null
      MESSAGE = "no CI adapter is configured (WarpEngine.config.ci_adapter)".freeze

      def name = "none"
      def configured? = false
      def platforms = {}
      def built_kinds(_platform) = nil
      def update_server = nil

      def repos                              = raise(NotConfigured, MESSAGE)
      def repo(_id)                          = raise(NotConfigured, MESSAGE)
      def activate_repo(_id)                 = raise(NotConfigured, MESSAGE)
      def deactivate_repo(_id)               = raise(NotConfigured, MESSAGE)
      def runs(_repo_id, page: 1)            = raise(NotConfigured, MESSAGE)
      def run(_repo_id, _number)             = raise(NotConfigured, MESSAGE)
      def trigger(_repo_id, branch: nil)     = raise(NotConfigured, MESSAGE)
      def secret_names(_repo_id)             = raise(NotConfigured, MESSAGE)
      def secret_set(_repo_id, name:, value:) = raise(NotConfigured, MESSAGE)
      def secret_delete(_repo_id, _name)     = raise(NotConfigured, MESSAGE)

      def verify_config_request(_request) = false
      def config_marker(_params) = nil
      def pipeline_config(platform:, name:, update_server:) = nil
      def config_response(platform:, config:) = {}
    end

    class << self
      def adapter
        configured = WarpEngine.config.ci_adapter

        case configured
        when nil, :woodpecker, "woodpecker" then woodpecker_adapter
        when :gitlab, "gitlab"              then gitlab_adapter
        when :none, "none", :null           then null_adapter
        else configured
        end
      end

      def woodpecker? = adapter.is_a?(Woodpecker::Adapter)
      def gitlab?     = adapter.is_a?(Gitlab::Adapter)

      def woodpecker_adapter
        @woodpecker_adapter ||= Woodpecker::Adapter.new
      end

      def gitlab_adapter
        @gitlab_adapter ||= Gitlab::Adapter.new
      end

      def null_adapter
        @null_adapter ||= Null.new
      end

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
