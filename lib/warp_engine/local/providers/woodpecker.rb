require "securerandom"

module WarpEngine
  module Local
    module Providers
      # The CI: a Woodpecker server (<tt><prefix>-woodpecker</tt>) and agent
      # (<tt><prefix>-woodpecker-agent</tt>, running the pipelines on the machine's
      # Docker through its socket), signed in to the git server through an
      # OAuth app there, asking this engine for the pipelines
      # (<tt>/build/config</tt>). It needs the SCM
      # (WarpEngine::Local::Providers::Gitea). No port is published: the
      # engine reaches it on the network (with WarpEngine::Local::Configuration#ci_port
      # its web UI answers on 127.0.0.1 too, signed in through the git server's
      # public address), and the pipelines reach the git server's public address
      # through a git +insteadOf+ rule. Its adapter is
      # the configured WarpEngine::CI::Woodpecker::Adapter with this server.
      class Woodpecker < Provider
        # The server image, at a fixed version.
        SERVER_IMAGE = "woodpeckerci/woodpecker-server:v3.20.1".freeze

        # The agent image, at the same version.
        AGENT_IMAGE = "woodpeckerci/woodpecker-agent:v3.20.1".freeze

        # The server's web port inside the network.
        PORT = 8000

        # The name of the OAuth app on the SCM.
        OAUTH_APP = "Woodpecker (local)".freeze

        # Returns <tt>"woodpecker"</tt>.
        def self.key = "woodpecker"

        # Returns the human name.
        def self.label = "CI (Woodpecker)"

        # Returns +:ci+.
        def self.role = :ci

        # Returns +[:scm]+.
        def self.requires = [ :scm ]

        # Returns what it is.
        def self.description = "Builds every push and tag with the pipeline this engine serves, and publishes here."

        # Returns the server container, also its address on the network.
        def server = config.name("woodpecker")

        # Returns the agent container.
        def agent = config.name("woodpecker-agent")

        # Returns the volume of the server's data.
        def volume = config.name("woodpecker-data")

        # Returns the address inside the network.
        def internal_url = "http://#{server}:#{PORT}"

        # Returns the address on this machine, or +nil+ without a CI port.
        def public_url = config.ci_port ? "http://localhost:#{config.ci_port}" : nil

        # Returns the address people and the SCM's OAuth redirect use: the public one, else the internal one.
        def host_url = public_url || internal_url

        # Fetches the SCM's and its own public addresses from the internal ones.
        def rewrites
          own = public_url ? { "#{public_url}/" => "#{internal_url}/", public_url => internal_url } : {}
          (scm&.rewrites || {}).merge(own)
        end

        # Returns the SCM provider (WarpEngine::Local::Providers::Gitea), or +nil+.
        def scm
          record = LocalProvider.find_by(role: "scm")
          record&.provider
        end

        # Makes the OAuth app on the SCM and the agent secret, unless there.
        def prepare(task)
          git = scm or raise Local::Error, "the CI needs the git server"
          store!(secrets: { "agent_secret" => SecureRandom.hex(24) }) if secret("agent_secret").blank?
          redirect = "#{host_url}/authorize"
          return if secret("client_id").present? && setting("redirect") == redirect && oauth_app?(git)

          task.step!("register the CI on the git server")
          _, apps = git.api(:get, "/user/applications/oauth2")
          Array(apps).select { |app| app["name"] == OAUTH_APP }.each { |app| git.api(:delete, "/user/applications/oauth2/#{app['id']}") }
          status, body = git.api(:post, "/user/applications/oauth2", { name: OAUTH_APP, redirect_uris: [ redirect ],
                                                                         confidential_client: true, skip_secondary_authorization: true })
          raise Local::Error, "gitea did not make the OAuth app: #{body['message'] || status}" unless status == 201

          store!(settings: { "redirect" => redirect }, secrets: { "client_id" => body["client_id"], "client_secret" => body["client_secret"] })
        end

        # Returns the server and the agent.
        def containers
          git = scm
          public_git = git ? "#{git.public_url}/" : ""
          [ ContainerSpec.build(name: server, image: SERVER_IMAGE, volumes: { volume => "/var/lib/woodpecker" }, ports: published, env: {
              **oauth_hosts(git), "WOODPECKER_HOST" => host_url, "WOODPECKER_SERVER_ADDR" => ":#{PORT}", "WOODPECKER_OPEN" => "true",
              "WOODPECKER_ADMIN" => Gitea::ADMIN, "WOODPECKER_GITEA" => "true", "WOODPECKER_GITEA_URL" => git&.internal_url.to_s,
              "WOODPECKER_GITEA_CLIENT" => secret("client_id").to_s, "WOODPECKER_GITEA_SECRET" => secret("client_secret").to_s,
              "WOODPECKER_AGENT_SECRET" => secret("agent_secret").to_s,
              "WOODPECKER_CONFIG_EXTENSION_ENDPOINT" => "#{config.engine_url}/build/config",
              "WOODPECKER_EXTENSIONS_ALLOWED_HOSTS" => config.engine_host.to_s,
              "WOODPECKER_ENVIRONMENT" => "GIT_CONFIG_COUNT:1,GIT_CONFIG_KEY_0:url.#{git&.internal_url}/.insteadOf,GIT_CONFIG_VALUE_0:#{public_git}"
            }),
            ContainerSpec.build(name: agent, image: AGENT_IMAGE, binds: [ "#{config.host_socket}:/var/run/docker.sock" ], env: {
              "WOODPECKER_SERVER" => "#{server}:9000", "WOODPECKER_AGENT_SECRET" => secret("agent_secret").to_s,
              "WOODPECKER_BACKEND_DOCKER_NETWORK" => config.network, "WOODPECKER_MAX_WORKFLOWS" => "2"
            }) ]
        end

        # Returns the sign-in for the web UI: the git server's administrator.
        def credentials
          { url: host_url, user: Gitea::ADMIN, password: scm&.secret("admin_password") }
        end

        # Returns +true+ when the server answers its health check.
        def healthy? = http.up?("#{internal_url}/healthz")

        # Signs in through the SCM as its administrator, keeps the API
        # token, and stores the SCM token as the global +gitea_token+ secret.
        def bootstrap(task)
          unless secret("token").present? && http.json(:get, "#{internal_url}/api/user", bearer: secret("token")).first == 200
            task.step!("sign the engine in to the CI")
            store!(secrets: { "token" => sign_in })
          end
          task.step!("store the gitea_token secret")
          upsert_secret("gitea_token", scm&.secret("token").to_s)
          store!(settings: { "url" => internal_url })
        end

        # Returns +base+ (the configured WarpEngine::CI::Woodpecker::Adapter)
        # pointed at this server, or +nil+ before the token.
        def adapter(base = nil)
          return nil if secret("token").blank? || !base.respond_to?(:with)

          base.with(url: internal_url, api_token: secret("token"), repo_owner: config.owner,
                    public_key_url: "#{internal_url}/api/signature/public-key", update_server: config.engine_url)
        end

        private

        def published = config.ci_port ? { config.ci_port => PORT } : {}

        def oauth_hosts(git)
          return {} unless public_url && git

          { "WOODPECKER_EXPERT_FORGE_OAUTH_HOST" => git.public_url, "WOODPECKER_EXPERT_WEBHOOK_HOST" => internal_url }
        end

        def oauth_app?(git)
          _, apps = git.api(:get, "/user/applications/oauth2")
          Array(apps).any? { |app| app["client_id"] == secret("client_id") }
        end

        def sign_in
          git = scm
          login(git)
          url = "#{internal_url}/authorize"
          response = http.get(url)
          10.times do
            response = grant(git, url, response) if response.is_a?(Net::HTTPOK) && http.rewrite(url).start_with?(git.internal_url)
            break unless response.is_a?(Net::HTTPRedirection)

            url = URI.join(http.rewrite(url), response["location"]).to_s
            response = http.get(url)
          end
          raise Local::Error, "the CI sign-in did not finish (#{response.code})" if http.cookie(internal_url, "user_sess").blank?

          csrf = http.get("#{internal_url}/web-config.js").body.to_s[/WOODPECKER_CSRF\s*=\s*"([^"]+)"/, 1]
          raise Local::Error, "the CI sent no CSRF token" if csrf.nil?

          created = http.post_json("#{internal_url}/api/user/token", {}, headers: { "X-CSRF-TOKEN" => csrf })
          raise Local::Error, "the CI did not issue a token (#{created.code})" unless created.is_a?(Net::HTTPSuccess)

          created.body.strip
        end

        def login(git)
          page = http.get("#{git.internal_url}/user/login").body.to_s
          form = { "user_name" => Gitea::ADMIN, "password" => git.secret("admin_password") }
          csrf = page[/name="_csrf"\s+value="([^"]+)"/, 1]
          form["_csrf"] = csrf if csrf
          response = http.post_form("#{git.internal_url}/user/login", form, headers: { "Origin" => git.internal_url })
          raise Local::Error, "gitea refused the #{Gitea::ADMIN} sign-in" unless response.is_a?(Net::HTTPRedirection)
        end

        def grant(git, url, page)
          form = page.body.to_s[%r{<form[^>]*action="/login/oauth/grant".*?</form>}m]
          return page if form.nil?

          fields = form.scan(/<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"/).to_h
          http.post_form(URI.join(http.rewrite(url), "/login/oauth/grant").to_s, fields.merge("granted" => "true"),
                         headers: { "Origin" => git.internal_url })
        end

        def upsert_secret(name, value)
          body = { name: name, value: value, events: %w[push tag deployment pull_request manual] }
          status, = http.json(:post, "#{internal_url}/api/secrets", body, bearer: secret("token"))
          return if status.between?(200, 299)

          status, = http.json(:patch, "#{internal_url}/api/secrets/#{name}", body, bearer: secret("token"))
          raise Local::Error, "the CI did not store #{name} (#{status})" unless status.between?(200, 299)
        end
      end
    end
  end
end
