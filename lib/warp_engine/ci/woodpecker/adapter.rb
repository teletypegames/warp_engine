module WarpEngine
  module CI
    # The Woodpecker CI provider: CI::Woodpecker::Adapter, its API client, the
    # config extension signature check and the pipeline renderer with the bundled
    # <tt>platforms/<platform>/pipeline.yaml.erb</tt> templates.
    module Woodpecker
      # The CI adapter for Woodpecker CI. It talks to the Woodpecker API through a
      # CI::Woodpecker::Client, serves generated pipelines as a Woodpecker
      # configuration extension (<tt>POST /build/config</tt>, httpsig-signed requests
      # checked by CI::Woodpecker::SignatureVerifier) and renders them with
      # CI::Woodpecker::PipelineConfig.
      class Adapter
        # The pipeline events a secret created by #secret_set is available to.
        SECRET_EVENTS = %w[push tag deployment].freeze

        # The Woodpecker server URL, the owner whose repositories the catalog builds,
        # and the catalog URL the generated pipelines upload to (each +nil+ when unset).
        attr_reader :url, :repo_owner, :update_server

        # Creates the adapter. Blank values count as unset.
        #
        # [url]            the Woodpecker server URL (+WOODPECKER_URL+)
        # [api_token]      the Woodpecker API token (+WOODPECKER_API_TOKEN+)
        # [repo_owner]     the repository owner (+WOODPECKER_REPO_OWNER+)
        # [public_key]     the PEM public key config requests are signed with
        # [public_key_url] the URL to fetch that public key from, when +public_key+ is not given
        # [platforms]      the platforms to build, see CI::PipelineConfig.new
        # [update_server]  the catalog URL the pipelines upload to
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

        # Returns the display name, <tt>"Woodpecker"</tt>.
        def name = "Woodpecker"

        # Returns what the admin may see of the configuration, as
        # <tt>[label, value]</tt> pairs; the token and the key only as set or not.
        def settings
          signature = if @public_key then "public key in the configuration"
          elsif @public_key_url then "public key fetched from #{@public_key_url}"
          else "not set: every config request is refused"
          end
          [ [ "Server", @url || "not set (WOODPECKER_URL)" ], [ "Repo owner", @repo_owner || "not set" ],
            [ "API token", @api_token ? "set" : "not set (WOODPECKER_API_TOKEN)" ], [ "Config signature", signature ] ]
        end

        # Returns +true+ when both the server URL and the API token are set.
        def configured? = @url.present? && @api_token.present?

        # Returns the configured platforms (see CI::PipelineConfig#platforms).
        def platforms = @config.platforms

        # Returns the release file kinds the pipeline of +platform+ builds, or +nil+
        # (see CI::PipelineConfig#built_kinds).
        def built_kinds(platform) = @config.built_kinds(platform)

        # Returns the memoized CI::Woodpecker::Client for the configured URL and token.
        def client
          @client ||= Client.new(url: @url, token: @api_token)
        end

        # Returns every repository the API token can see, as an Array of CI::Repo.
        # Raises CI::ConnectionError or CI::ApiError.
        def repos
          Array(client.list_repos).map { |remote| to_repo(remote) }
        end

        # Returns the CI::Repo of +repo_id+ (the Woodpecker repository id). Raises CI::ApiError when it is not found.
        def repo(repo_id)
          to_repo(client.get_repo(repo_id))
        end

        # Enables CI for the repository +repo_id+ on the server. Returns +nil+. Raises CI::ApiError.
        def activate_repo(repo_id)
          client.activate_repo(repo_id)
          nil
        end

        # Disables CI for the repository +repo_id+ on the server. Returns +nil+. Raises CI::ApiError.
        def deactivate_repo(repo_id)
          client.deactivate_repo(repo_id)
          nil
        end

        # Returns one page (25 runs, newest first) of the pipeline runs of +repo_id+ as an Array of CI::Run.
        def runs(repo_id, page: 1)
          Array(client.list_pipelines(repo_id, page: page)).map { |run| to_run(run) }
        end

        # Returns the CI::Run numbered +number+ of +repo_id+, or the latest run when
        # +number+ is <tt>"latest"</tt>; +nil+ when there is no latest run. Raises
        # CI::ApiError when the run is not found.
        def run(repo_id, number)
          remote = if number.to_s == "latest"
            client.latest_pipeline(repo_id)
          else
            client.get_pipeline(repo_id, number)
          end
          remote && to_run(remote)
        end

        # Starts a pipeline of +repo_id+ on +branch+ (+main+ when +nil+). Returns the new CI::Run.
        def trigger(repo_id, branch: "main")
          to_run(client.trigger_pipeline(repo_id, branch: branch || "main"))
        end

        # Returns the names of the secrets of +repo_id+ as an Array of Strings.
        def secret_names(repo_id)
          Array(client.list_secrets(repo_id)).map { |secret| secret["name"] }
        end

        # Creates or updates the secret +name+ of +repo_id+ with +value+. A new secret is
        # available to the SECRET_EVENTS events. Returns +nil+.
        def secret_set(repo_id, name:, value:)
          if secret_names(repo_id).include?(name)
            client.update_secret(repo_id, name, value: value)
          else
            client.create_secret(repo_id, name: name, value: value, events: SECRET_EVENTS)
          end
          nil
        end

        # Deletes the secret +name+ of +repo_id+. Returns +nil+. Raises CI::ApiError when it does not exist.
        def secret_delete(repo_id, name)
          client.delete_secret(repo_id, name)
          nil
        end

        # Returns +true+ when the config extension +request+ carries a valid signature of the configured public key.
        def verify_config_request(request)
          SignatureVerifier.new(request, public_key: @public_key, public_key_url: @public_key_url).valid?
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
