module WarpEngine
  module CI
    module Gitlab
      class Adapter
        attr_reader :url, :update_server

        def initialize(url: ENV["GITLAB_URL"],
                       api_token: ENV["GITLAB_API_TOKEN"],
                       webhook_secret: ENV["GITLAB_WEBHOOK_SECRET"],
                       platforms: {},
                       update_server: nil)
          @url            = url.presence
          @api_token      = api_token.presence
          @webhook_secret = webhook_secret.presence
          @update_server  = update_server.presence
          @config         = PipelineConfig.new(platforms: platforms || {})
        end

        def name = "GitLab"

        def configured? = @url.present? && @api_token.present?

        def platforms = @config.platforms

        def built_kinds(platform) = @config.built_kinds(platform)

        def client
          @client ||= Client.new(url: @url, token: @api_token)
        end

        def repos
          Array(client.list_repos).map { |remote| to_repo(remote) }
        end

        def repo(project_id)
          to_repo(client.get_repo(project_id))
        end

        def activate_repo(project_id)
          client.activate_repo(project_id)
          nil
        end

        def deactivate_repo(project_id)
          client.deactivate_repo(project_id)
          nil
        end

        def runs(project_id, page: 1)
          Array(client.list_pipelines(project_id, page: page)).map { |run| to_run(run) }
        end

        def run(project_id, number)
          remote = if number.to_s == "latest"
            client.latest_pipeline(project_id)
          else
            client.get_pipeline(project_id, number)
          end
          remote && to_run(remote)
        end

        def trigger(project_id, branch: "main")
          to_run(client.trigger_pipeline(project_id, branch: branch || "main"))
        end

        def secret_names(project_id)
          Array(client.list_secrets(project_id)).map { |var| var["key"] }
        end

        def secret_set(project_id, name:, value:)
          if secret_names(project_id).include?(name)
            client.update_secret(project_id, name, value: value)
          else
            client.create_secret(project_id, name: name, value: value)
          end
          nil
        end

        def secret_delete(project_id, name)
          client.delete_secret(project_id, name)
          nil
        end

        def verify_config_request(request)
          SignatureVerifier.new(request, webhook_secret: @webhook_secret).valid?
        end

        def config_marker(params)
          configs = params[:configuration].presence || params[:configs].presence || []
          configs = Array(configs)
          configs.each_with_index do |config, index|
            parsed = parse_marker(config[:data].to_s)
            next unless parsed

            marker = { platform: parsed["platform"].to_s,
                       name:     parsed["name"].presence || params.dig(:repo, :name).to_s }
            options = parsed.except("platform", "name")
            marker[:options] = options if options.any?
            others = configs.reject.with_index { |_, other| other == index }
                            .map { |other| { name: other[:name].to_s, data: other[:data].to_s } }
            marker[:others] = others if others.any?
            return marker
          end
          nil
        end

        def pipeline_config(platform:, name:, update_server:, options: {})
          @config.render(platform: platform, name: name, update_server: update_server, options: options)
        end

        def config_response(platform:, config:, others: [])
          { configs: [ { name: platform, data: config } ] + others }
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

          namespace = remote.dig("namespace", "path") || remote.dig("namespace", "name")
          Repo.new(id: remote["id"], name: remote["path"] || remote["name"],
                   owner: namespace, active: true, raw: remote)
        end

        def to_run(remote)
          return nil if remote.nil?

          created = remote["created_at"] ? Time.zone.parse(remote["created_at"]) : nil
          Run.new(
            number:     remote["id"],
            status:     remote["status"],
            branch:     remote["ref"],
            message:    nil,
            created_at: created,
            url:        remote["web_url"],
            raw:        remote
          )
        end
      end
    end
  end
end
