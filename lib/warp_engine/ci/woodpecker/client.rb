require "net/http"
require "json"
require "uri"

module WarpEngine
  module CI
    module Woodpecker
      # A minimal JSON client of the Woodpecker REST API, authenticated with a
      # bearer token. Every call returns the parsed JSON (+nil+ for an empty body),
      # raises CI::ConnectionError when the server cannot be reached and
      # CI::ApiError for an error status or a non-JSON body.
      class Client
        # [url]   the Woodpecker server URL (a trailing slash is dropped)
        # [token] the API token sent as <tt>Authorization: Bearer</tt>
        def initialize(url:, token:)
          @base_url = url.to_s.chomp("/")
          @token    = token
        end

        # <tt>GET /api/repos</tt>: returns the Array of repository Hashes the token can see.
        def list_repos
          get("/api/repos")
        end

        # <tt>GET /api/repos/:repo_id</tt>: returns the repository Hash.
        def get_repo(repo_id)
          get("/api/repos/#{repo_id}")
        end

        # <tt>POST /api/repos</tt>: enables CI for the forge repository +repo_id+.
        def activate_repo(repo_id)
          post("/api/repos", body: { id: repo_id })
        end

        # <tt>DELETE /api/repos/:repo_id</tt>: disables CI for the repository.
        def deactivate_repo(repo_id)
          delete("/api/repos/#{repo_id}")
        end

        # <tt>GET /api/repos/:repo_id/secrets</tt>: returns the Array of secret Hashes (without values).
        def list_secrets(repo_id)
          get("/api/repos/#{repo_id}/secrets")
        end

        # <tt>POST /api/repos/:repo_id/secrets</tt>: creates the secret +name+ with +value+, available to the +events+.
        def create_secret(repo_id, name:, value:, events: %w[push tag deployment])
          post("/api/repos/#{repo_id}/secrets",
               body: { name: name, value: value, events: events })
        end

        # <tt>PATCH /api/repos/:repo_id/secrets/:secret_name</tt>: sets a new +value+.
        def update_secret(repo_id, secret_name, value:)
          patch("/api/repos/#{repo_id}/secrets/#{secret_name}",
                body: { value: value })
        end

        # <tt>DELETE /api/repos/:repo_id/secrets/:secret_name</tt>: deletes the secret.
        def delete_secret(repo_id, secret_name)
          delete("/api/repos/#{repo_id}/secrets/#{secret_name}")
        end

        # <tt>GET /api/repos/:repo_id/pipelines</tt>: returns one page of pipeline Hashes.
        def list_pipelines(repo_id, page: 1, per_page: 25)
          get("/api/repos/#{repo_id}/pipelines",
              params: { page: page, perPage: per_page })
        end

        # <tt>GET /api/repos/:repo_id/pipelines/latest</tt>: returns the latest pipeline Hash.
        def latest_pipeline(repo_id)
          get("/api/repos/#{repo_id}/pipelines/latest")
        end

        # <tt>GET /api/repos/:repo_id/pipelines/:number</tt>: returns the pipeline Hash.
        def get_pipeline(repo_id, number)
          get("/api/repos/#{repo_id}/pipelines/#{number}")
        end

        # <tt>POST /api/repos/:repo_id/pipelines</tt>: starts a pipeline on +branch+ and returns its Hash.
        def trigger_pipeline(repo_id, branch: "main")
          post("/api/repos/#{repo_id}/pipelines",
               body: { branch: branch })
        end

        private

        def get(path, params: {})
          uri = build_uri(path, params)
          execute(uri, Net::HTTP::Get.new(uri))
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
          execute(uri, Net::HTTP::Delete.new(uri))
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
          raise CI::ConnectionError, "Cannot reach Woodpecker at #{@base_url}: #{e.message}"
        end

        def handle_response(uri, response)
          case response
          when Net::HTTPSuccess, Net::HTTPNoContent
            return nil if response.body.blank?

            begin
              JSON.parse(response.body)
            rescue JSON::ParserError
              raise CI::ApiError.new(
                "Expected JSON from #{uri.path} but got: #{response.body.truncate(80)}",
                status: response.code.to_i, body: response.body
              )
            end
          when Net::HTTPNotFound
            raise CI::ApiError.new("Not found: #{uri.path}", status: 404, body: response.body)
          else
            raise CI::ApiError.new(
              "Woodpecker API error #{response.code}: #{response.body&.truncate(200)}",
              status: response.code.to_i,
              body: response.body
            )
          end
        end
      end
    end
  end
end
