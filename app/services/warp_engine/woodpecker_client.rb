require "net/http"
require "json"
require "uri"

module WarpEngine
  class WoodpeckerClient
    class ApiError < StandardError
      attr_reader :status, :body

      def initialize(message, status:, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    class ConnectionError < StandardError; end

    def initialize(base_url: nil, token: nil)
      @base_url = (base_url || WarpEngine.config.woodpecker_url).to_s.chomp("/")
      @token    = token || WarpEngine.config.woodpecker_api_token
    end

    def list_repos
      get("/api/repos")
    end

    def get_repo(repo_id)
      get("/api/repos/#{repo_id}")
    end

    def activate_repo(repo_id)
      post("/api/repos", body: { id: repo_id })
    end

    def deactivate_repo(repo_id)
      delete("/api/repos/#{repo_id}")
    end

    def list_secrets(repo_id)
      get("/api/repos/#{repo_id}/secrets")
    end

    def create_secret(repo_id, name:, value:, events: %w[push tag deployment])
      post("/api/repos/#{repo_id}/secrets",
           body: { name: name, value: value, events: events })
    end

    def update_secret(repo_id, secret_name, value:)
      patch("/api/repos/#{repo_id}/secrets/#{secret_name}",
            body: { value: value })
    end

    def delete_secret(repo_id, secret_name)
      delete("/api/repos/#{repo_id}/secrets/#{secret_name}")
    end

    def list_pipelines(repo_id, page: 1, per_page: 25)
      get("/api/repos/#{repo_id}/pipelines",
          params: { page: page, perPage: per_page })
    end

    def latest_pipeline(repo_id)
      get("/api/repos/#{repo_id}/pipelines/latest")
    end

    def get_pipeline(repo_id, number)
      get("/api/repos/#{repo_id}/pipelines/#{number}")
    end

    def trigger_pipeline(repo_id, branch: "main")
      post("/api/repos/#{repo_id}/pipelines",
           body: { branch: branch })
    end

    private

    def get(path, params: {})
      uri = build_uri(path, params)
      request = Net::HTTP::Get.new(uri)
      execute(uri, request)
    end

    def post(path, body: {})
      uri = build_uri(path)
      request = Net::HTTP::Post.new(uri)
      request.body = body.to_json
      request.content_type = "application/json"
      execute(uri, request)
    end

    def patch(path, body: {})
      uri = build_uri(path)
      request = Net::HTTP::Patch.new(uri)
      request.body = body.to_json
      request.content_type = "application/json"
      execute(uri, request)
    end

    def delete(path)
      uri = build_uri(path)
      request = Net::HTTP::Delete.new(uri)
      execute(uri, request)
    end

    def build_uri(path, params = {})
      uri = URI.parse("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      uri
    end

    def execute(uri, request)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.hostname, uri.port,
                                  use_ssl: uri.scheme == "https",
                                  open_timeout: 10,
                                  read_timeout: 30) do |http|
        http.request(request)
      end

      handle_response(uri, response)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout,
           Net::ReadTimeout, SocketError => e
      raise ConnectionError, "Cannot reach Woodpecker at #{@base_url}: #{e.message}"
    end

    def handle_response(uri, response)
      case response
      when Net::HTTPSuccess, Net::HTTPNoContent
        return nil if response.body.blank?
        begin
          JSON.parse(response.body)
        rescue JSON::ParserError

          raise ApiError.new(
            "Expected JSON from #{uri.path} but got: #{response.body.truncate(80)}",
            status: response.code.to_i, body: response.body
          )
        end
      when Net::HTTPNotFound
        raise ApiError.new("Not found: #{uri.path}", status: 404, body: response.body)
      else
        raise ApiError.new(
          "Woodpecker API error #{response.code}: #{response.body&.truncate(200)}",
          status: response.code.to_i,
          body: response.body
        )
      end
    end
  end
end
