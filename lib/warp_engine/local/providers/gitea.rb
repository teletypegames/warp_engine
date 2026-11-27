require "securerandom"

module WarpEngine
  module Local
    module Providers
      # The git server: Gitea in the container <tt><prefix>-gitea</tt>
      # (WarpEngine::Local::Configuration#name_prefix), its web
      # and git address published on 127.0.0.1 at the SCM port
      # (WarpEngine::Local::Configuration#scm_port), its data in the volume
      # <tt><prefix>-gitea-data</tt>. The bootstrap makes an administrator, the
      # organisation (WarpEngine::Local::Configuration#owner), an API token for
      # the engine and a push user, all with generated passwords; nobody signs
      # in. Its adapter is a WarpEngine::Scm::Gitea on the internal address.
      class Gitea < Provider
        # The image, at a fixed version.
        IMAGE = "gitea/gitea:1.27.3".freeze

        # The port it answers on inside the network.
        PORT = 3000

        # The administrator the engine works as.
        ADMIN = "warp-admin".freeze

        # The user a developer's git pushes as.
        PUSHER = "warp".freeze

        # The scopes of the engine's API token.
        TOKEN_SCOPES = %w[write:repository write:organization write:issue write:user write:admin read:user].freeze

        # Returns <tt>"gitea"</tt>.
        def self.key = "gitea"

        # Returns the human name.
        def self.label = "Git server (Gitea)"

        # Returns +:scm+.
        def self.role = :scm

        # Returns what it is.
        def self.description = "A git server your projects are pushed to; the CI builds from it."

        # Returns the container name, also its address on the network.
        def container = config.name("gitea")

        # Returns the volume of its data.
        def volume = config.name("gitea-data")

        # Returns the address inside the network.
        def internal_url = "http://#{container}:#{PORT}"

        # Returns the address on this machine.
        def public_url = "http://localhost:#{config.scm_port}"

        # Fetches the public address from the internal one.
        def rewrites = { "#{public_url}/" => "#{internal_url}/", public_url => internal_url }

        # Returns its container.
        def containers
          [ ContainerSpec.build(
            name: container, image: IMAGE, volumes: { volume => "/data" }, ports: { config.scm_port => PORT },
            env: {
              "GITEA__security__INSTALL_LOCK" => "true", "GITEA__server__DOMAIN" => "localhost",
              "GITEA__server__HTTP_PORT" => PORT.to_s, "GITEA__server__ROOT_URL" => "#{public_url}/",
              "GITEA__server__PUBLIC_URL_DETECTION" => "never",
              "GITEA__server__DISABLE_SSH" => "true", "GITEA__service__DISABLE_REGISTRATION" => "true",
              "GITEA__webhook__ALLOWED_HOST_LIST" => "*", "GITEA__repository__DEFAULT_BRANCH" => "master"
            }
          ) ]
        end

        # Returns +true+ when it answers its health check.
        def healthy? = http.up?("#{internal_url}/api/healthz")

        # Makes the administrator, the organisation, the engine's token and the push user, unless there.
        def bootstrap(task)
          ensure_admin(task)
          ensure_org(task)
          ensure_token(task)
          ensure_pusher(task)
          store!(settings: { "url" => internal_url, "publicUrl" => public_url, "owner" => config.owner })
        end

        # Returns a WarpEngine::Scm::Gitea on the internal address, or +nil+ before the token.
        def adapter(_base = nil)
          return nil if secret("token").blank?

          WarpEngine::Scm::Gitea.new(url: internal_url, token: secret("token"), owner: config.owner)
        end

        # Lets the push user write to the repository of +software+ and adds
        # +pushUrl+ (with the push user's token) to +result+.
        def connect(software, task, result)
          name = software.name
          task.step!("let #{PUSHER} push to #{config.owner}/#{name}")
          status, body = api(:put, "/repos/#{config.owner}/#{name}/collaborators/#{PUSHER}", { permission: "write" })
          raise Local::Error, "gitea: #{body['message'] || status}" unless [ 204, 200 ].include?(status)

          result[:pushUrl] = "http://#{PUSHER}:#{secret('pusher_token')}@localhost:#{config.scm_port}/#{config.owner}/#{name}.git"
          result[:repoUrl] = "#{public_url}/#{config.owner}/#{name}"
        end

        # Returns the administrator's sign-in.
        def credentials = { url: public_url, user: ADMIN, password: secret("admin_password") }

        # Returns the administrator's basic auth.
        def admin_auth = [ ADMIN, secret("admin_password") ]

        # Calls the Gitea API as the administrator. Returns <tt>[status, body]</tt>.
        def api(method, path, body = nil) = http.json(method, "#{internal_url}/api/v1#{path}", body, basic: admin_auth)

        private

        def ensure_admin(task)
          store!(secrets: { "admin_password" => SecureRandom.hex(16) }) if secret("admin_password").blank?
          return if api(:get, "/user").first == 200

          task.step!("create the administrator #{ADMIN}")
          code, output = runtime.exec(container, [ "gitea", "admin", "user", "create", "--admin", "--username", ADMIN,
                                                   "--password", secret("admin_password"), "--email", "#{ADMIN}@warp-engine.local",
                                                   "--must-change-password=false" ], user: "git")
          if code != 0 && output.include?("already exists")
            code, output = runtime.exec(container, [ "gitea", "admin", "user", "change-password", "--username", ADMIN,
                                                     "--password", secret("admin_password"), "--must-change-password=false" ], user: "git")
          end
          raise Local::Error, "gitea did not make #{ADMIN}: #{output.strip}" unless code.zero?
        end

        def ensure_org(task)
          return if api(:get, "/orgs/#{config.owner}").first == 200

          task.step!("create the organisation #{config.owner}")
          status, body = api(:post, "/orgs", { username: config.owner, visibility: "public" })
          raise Local::Error, "gitea did not make #{config.owner}: #{body['message'] || status}" unless status == 201
        end

        def ensure_token(task)
          return if secret("token").present? && http.json(:get, "#{internal_url}/api/v1/user", token: secret("token")).first == 200

          task.step!("issue the engine's gitea token")
          status, body = api(:post, "/users/#{ADMIN}/tokens", { name: "warp-engine-#{SecureRandom.hex(3)}", scopes: TOKEN_SCOPES })
          raise Local::Error, "gitea did not issue a token: #{body['message'] || status}" unless status == 201

          store!(secrets: { "token" => body["sha1"] })
        end

        def ensure_pusher(task)
          store!(secrets: { "pusher_password" => SecureRandom.hex(16) }) if secret("pusher_password").blank?
          if api(:get, "/users/#{PUSHER}").first == 404
            task.step!("create the push user #{PUSHER}")
            status, body = api(:post, "/admin/users", { username: PUSHER, email: "#{PUSHER}@warp-engine.local", password: secret("pusher_password"),
                                                         must_change_password: false })
            raise Local::Error, "gitea did not make #{PUSHER}: #{body['message'] || status}" unless status == 201
          end
          return if pusher_token_valid?

          api(:patch, "/admin/users/#{PUSHER}", { login_name: PUSHER, source_id: 0, password: secret("pusher_password"),
                                                  must_change_password: false })
          status, body = http.json(:post, "#{internal_url}/api/v1/users/#{PUSHER}/tokens",
                                   { name: "git-#{SecureRandom.hex(3)}", scopes: %w[write:repository] },
                                   basic: [ PUSHER, secret("pusher_password") ])
          raise Local::Error, "gitea did not issue the push token: #{body['message'] || status}" unless status == 201

          store!(secrets: { "pusher_token" => body["sha1"] })
        end

        def pusher_token_valid?
          secret("pusher_token").present? &&
            http.json(:get, "#{internal_url}/api/v1/repos/search?limit=1", token: secret("pusher_token")).first == 200
        end
      end
    end
  end
end
