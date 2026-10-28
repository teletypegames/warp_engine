module WarpEngine
  module CI
    # The GitLab CI provider: CI::Gitlab::Adapter, its API client, the webhook
    # secret check and the pipeline renderer with the bundled
    # <tt>platforms/<platform>/pipeline.yaml.erb</tt> templates.
    module Gitlab
      # The CI adapter for GitLab CI. It talks to the GitLab REST API (v4) through a
      # CI::Gitlab::Client, accepts config requests carrying the webhook secret
      # (CI::Gitlab::SignatureVerifier) and renders pipelines with
      # CI::Gitlab::PipelineConfig. A GitLab project counts as a repository and its
      # CI/CD variables as secrets.
      class Adapter
        # The GitLab URL and the catalog URL the generated pipelines upload to (each +nil+ when unset).
        attr_reader :url, :update_server

        # Creates the adapter. Blank values count as unset.
        #
        # [url]            the GitLab URL (+GITLAB_URL+)
        # [api_token]      the GitLab API token (+GITLAB_API_TOKEN+)
        # [webhook_secret] the secret config requests must carry (+GITLAB_WEBHOOK_SECRET+)
        # [platforms]      the platforms to build, see CI::PipelineConfig.new
        # [update_server]  the catalog URL the pipelines upload to
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

        # Returns the display name, <tt>"GitLab"</tt>.
        def name = "GitLab"

        # Returns +true+ when both the server URL and the API token are set.
        def configured? = @url.present? && @api_token.present?

        # Returns the configured platforms (see CI::PipelineConfig#platforms).
        def platforms = @config.platforms

        # Returns the release file kinds the pipeline of +platform+ builds, or +nil+
        # (see CI::PipelineConfig#built_kinds).
        def built_kinds(platform) = @config.built_kinds(platform)

        # Returns the memoized CI::Gitlab::Client for the configured URL and token.
        def client
          @client ||= Client.new(url: @url, token: @api_token)
        end

        # Returns every repository the API token can see, as an Array of CI::Repo.
        # Raises CI::ConnectionError or CI::ApiError.
        def repos
          Array(client.list_repos).map { |remote| to_repo(remote) }
        end

        # Returns the CI::Repo of +project_id+ (the GitLab project id). Raises CI::ApiError when it is not found.
        def repo(project_id)
          to_repo(client.get_repo(project_id))
        end

        # Does nothing on GitLab, where CI needs no activation. Returns +nil+.
        def activate_repo(project_id)
          client.activate_repo(project_id)
          nil
        end

        # Does nothing on GitLab, where CI needs no activation. Returns +nil+.
        def deactivate_repo(project_id)
          client.deactivate_repo(project_id)
          nil
        end

        # Returns one page (25 runs, newest first) of the pipeline runs of +project_id+ as an Array of CI::Run.
        def runs(project_id, page: 1)
          Array(client.list_pipelines(project_id, page: page)).map { |run| to_run(run) }
        end

        # Returns the CI::Run numbered +number+ of +project_id+, or the latest run when
        # +number+ is <tt>"latest"</tt>; +nil+ when there is no latest run. Raises
        # CI::ApiError when the run is not found.
        def run(project_id, number)
          remote = if number.to_s == "latest"
            client.latest_pipeline(project_id)
          else
            client.get_pipeline(project_id, number)
          end
          remote && to_run(remote)
        end

        # Starts a pipeline of +project_id+ on +branch+ (+main+ when +nil+). Returns the new CI::Run.
        def trigger(project_id, branch: "main")
          to_run(client.trigger_pipeline(project_id, branch: branch || "main"))
        end

        # Returns the names of the secrets of +project_id+ as an Array of Strings: the
        # project's CI/CD variable keys.
        def secret_names(project_id)
          Array(client.list_secrets(project_id)).map { |var| var["key"] }
        end

        # Creates or updates the CI/CD variable +name+ of +project_id+ with +value+ (a new
        # one is masked and unprotected). Returns +nil+.
        def secret_set(project_id, name:, value:)
          if secret_names(project_id).include?(name)
            client.update_secret(project_id, name, value: value)
          else
            client.create_secret(project_id, name: name, value: value)
          end
          nil
        end

        # Deletes the secret +name+ of +project_id+. Returns +nil+. Raises CI::ApiError when it does not exist.
        def secret_delete(project_id, name)
          client.delete_secret(project_id, name)
          nil
        end

        # Returns +true+ when the config +request+ carries the configured webhook secret in <tt>X-Gitlab-Token</tt>.
        def verify_config_request(request)
          SignatureVerifier.new(request, webhook_secret: @webhook_secret).valid?
        end

        # Finds the marker among the repository's configs in a config request.
        #
        # [params] the request parameters: +configuration+ (or +configs+), an Array of
        #          Hashes with the config file's +name+ and +data+, and +repo+ with its +name+
        #
        # Returns +nil+ when no config is a YAML mapping with a +platform+ key.
        # Otherwise returns a Hash with +platform+, +name+ (the marker's, else the
        # repository's), +options+ (the marker's other keys, when any) and +others+
        # (the remaining configs as +name+/+data+ Hashes, when any).
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

        # Renders the pipeline of +platform+. Returns the YAML String or +nil+ (see CI::PipelineConfig#render).
        def pipeline_config(platform:, name:, update_server:, options: {})
          @config.render(platform: platform, name: name, update_server: update_server, options: options)
        end

        # Returns the body of the config response: the generated +config+ named after
        # +platform+, followed by the repository's +others+ configs unchanged.
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
