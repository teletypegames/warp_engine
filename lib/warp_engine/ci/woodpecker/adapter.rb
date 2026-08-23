module WarpEngine
  module CI
    module Woodpecker
      class Adapter
        SECRET_EVENTS = %w[push tag deployment].freeze

        attr_reader :url, :repo_owner, :update_server

        def initialize(url: ENV["WOODPECKER_URL"],
                       api_token: ENV["WOODPECKER_API_TOKEN"],
                       repo_owner: ENV["WOODPECKER_REPO_OWNER"],
                       public_key: nil,
                       public_key_url: nil,
                       platforms: {},
                       update_server: nil)
          @url            = url.presence
          @api_token      = api_token.presence
          @repo_owner     = repo_owner.presence
          @public_key     = public_key.presence
          @public_key_url = public_key_url.presence
          @update_server  = update_server.presence
          @config         = PipelineConfig.new(platforms: platforms || {})
        end

        def name = "Woodpecker"

        def configured? = @url.present? && @api_token.present?

        def platforms = @config.platforms

        def built_kinds(platform) = @config.built_kinds(platform)

        def client
          @client ||= Client.new(url: @url, token: @api_token)
        end

        def repos
          Array(client.list_repos).map { |remote| to_repo(remote) }
        end

        def repo(repo_id)
          to_repo(client.get_repo(repo_id))
        end

        def activate_repo(repo_id)
          client.activate_repo(repo_id)
          nil
        end

        def deactivate_repo(repo_id)
          client.deactivate_repo(repo_id)
          nil
        end

        def runs(repo_id, page: 1)
          Array(client.list_pipelines(repo_id, page: page)).map { |run| to_run(run) }
        end

        def run(repo_id, number)
          remote = if number.to_s == "latest"
            client.latest_pipeline(repo_id)
          else
            client.get_pipeline(repo_id, number)
          end
          remote && to_run(remote)
        end

        def trigger(repo_id, branch: "main")
          to_run(client.trigger_pipeline(repo_id, branch: branch || "main"))
        end

        def secret_names(repo_id)
          Array(client.list_secrets(repo_id)).map { |secret| secret["name"] }
        end

        def secret_set(repo_id, name:, value:)
          if secret_names(repo_id).include?(name)
            client.update_secret(repo_id, name, value: value)
          else
            client.create_secret(repo_id, name: name, value: value, events: SECRET_EVENTS)
          end
          nil
        end

        def secret_delete(repo_id, name)
          client.delete_secret(repo_id, name)
          nil
        end

        def verify_config_request(request)
          SignatureVerifier.new(request, public_key: @public_key, public_key_url: @public_key_url).valid?
        end

        def config_marker(params)
          configs = params[:configuration].presence || params[:configs].presence || []
          Array(configs).each do |config|
            parsed = parse_marker(config[:data].to_s)
            next unless parsed

            return { platform: parsed["platform"].to_s,
                     name:     parsed["name"].presence || params.dig(:repo, :name).to_s }
          end
          nil
        end

        def pipeline_config(platform:, name:, update_server:)
          @config.render(platform: platform, name: name, update_server: update_server)
        end

        def config_response(platform:, config:)
          { configs: [ { name: platform, data: config } ] }
        end

        private

        def parse_marker(data)
          parsed = begin
            YAML.safe_load(data)
          rescue Psych::Exception
            nil
          end
          parsed if parsed.is_a?(Hash) && parsed.key?("platform")
        end

        def to_repo(remote)
          return nil if remote.nil?

          Repo.new(id: remote["id"], name: remote["name"], owner: remote["owner"],
                   active: remote["active"], raw: remote)
        end

        def to_run(remote)
          return nil if remote.nil?

          Run.new(
            number:     remote["number"],
            status:     remote["status"],
            branch:     remote["branch"],
            message:    remote["message"],
            created_at: remote["created"] ? Time.zone.at(remote["created"]) : nil,
            url:        remote["forge_url"] || remote["link_url"],
            raw:        remote
          )
        end
      end
    end
  end
end
