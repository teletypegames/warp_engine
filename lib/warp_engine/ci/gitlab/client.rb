require "net/http"
require "json"
require "uri"

module WarpEngine
  module CI
    module Gitlab
      # A minimal JSON client of the GitLab REST API (v4), authenticated with a
      # <tt>PRIVATE-TOKEN</tt>. Every call returns the parsed JSON (+nil+ for an
      # empty body), raises CI::ConnectionError when the server cannot be reached
      # and CI::ApiError for an error status or a non-JSON body.
      class Client
        # [url]   the GitLab URL (a trailing slash is dropped)
        # [token] the access token sent as <tt>PRIVATE-TOKEN</tt>
        def initialize(url:, token:)
          @base_url = url.to_s.chomp("/")
          @token    = token
        end

        # <tt>GET /api/v4/projects</tt>: returns up to 100 project Hashes the token is a member of.
        def list_repos
          get("/api/v4/projects", params: { membership: true, simple: true, per_page: 100 })
        end

        # <tt>GET /api/v4/projects/:project_id</tt>: returns the project Hash.
        def get_repo(project_id)
          get("/api/v4/projects/#{project_id}")
        end

        # Does nothing and returns +nil+: GitLab CI needs no activation.
        def activate_repo(_project_id)
          nil
        end

        # Does nothing and returns +nil+: GitLab CI needs no activation.
        def deactivate_repo(_project_id)
          nil
        end

        # <tt>GET /api/v4/projects/:project_id/variables</tt>: returns the Array of CI/CD variable Hashes.
        def list_secrets(project_id)
          get("/api/v4/projects/#{project_id}/variables")
        end

        # <tt>POST /api/v4/projects/:project_id/variables</tt>: creates the masked, unprotected variable +name+.
        def create_secret(project_id, name:, value:)
          post("/api/v4/projects/#{project_id}/variables",
               body: { key: name, value: value, protected: false, masked: true })
        end

        # <tt>PUT /api/v4/projects/:project_id/variables/:secret_name</tt>: sets a new +value+.
        def update_secret(project_id, secret_name, value:)
          put("/api/v4/projects/#{project_id}/variables/#{secret_name}",
              body: { value: value })
        end

        # <tt>DELETE /api/v4/projects/:project_id/variables/:secret_name</tt>: deletes the variable.
        def delete_secret(project_id, secret_name)
          delete("/api/v4/projects/#{project_id}/variables/#{secret_name}")
        end

        # <tt>GET /api/v4/projects/:project_id/pipelines</tt>: returns one page of pipeline Hashes.
        def list_pipelines(project_id, page: 1, per_page: 25)
          get("/api/v4/projects/#{project_id}/pipelines",
              params: { page: page, per_page: per_page })
        end

        # Returns the newest pipeline Hash of the project, or +nil+ when it has none.
        def latest_pipeline(project_id)
          results = get("/api/v4/projects/#{project_id}/pipelines",
                        params: { per_page: 1, sort: "desc" })
          Array(results).first
        end

        # <tt>GET /api/v4/projects/:project_id/pipelines/:pipeline_id</tt>: returns the pipeline Hash.
        def get_pipeline(project_id, pipeline_id)
          get("/api/v4/projects/#{project_id}/pipelines/#{pipeline_id}")
        end

        # <tt>POST /api/v4/projects/:project_id/pipeline</tt>: starts a pipeline on the
        # +branch+ ref and returns its Hash.
        def trigger_pipeline(project_id, branch: "main")
          post("/api/v4/projects/#{project_id}/pipeline",
               body: { ref: branch })
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

        def put(path, body: {})
          uri = build_uri(path)
          request = Net::HTTP::Put.new(uri)
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
          request["PRIVATE-TOKEN"] = @token
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
          raise CI::ConnectionError, "Cannot reach GitLab at #{@base_url}: #{e.message}"
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
              "GitLab API error #{response.code}: #{response.body&.truncate(200)}",
              status: response.code.to_i,
              body: response.body
            )
          end
        end
      end
    end
  end
end
