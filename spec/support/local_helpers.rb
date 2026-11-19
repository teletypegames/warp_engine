module LocalHelpers
  class FakeRuntime < WarpEngine::Local::Runtime
    attr_reader :calls, :states

    def initialize
      super
      @calls = []
      @states = {}
      @exec_results = []
    end

    def available? = true
    def unavailable_reason = nil
    def ensure_network(name) = @calls << [ :network, name ]
    def pull(image) = @calls << [ :pull, image ]

    def run(spec, network:)
      @calls << [ :run, spec.name, network ]
      @states[spec.name] = "running"
    end

    def state(name) = @states[name]
    def stop(name) = (@calls << [ :stop, name ]) && @states[name] = "exited"

    def remove(name)
      @calls << [ :remove, name ]
      @states.delete(name)
    end

    def remove_volume(name) = @calls << [ :remove_volume, name ]

    def exec(name, cmd, user: nil)
      @calls << [ :exec, name, cmd.first(4), user ]
      @exec_results.shift || [ 0, "" ]
    end

    def exec_answers(*results) = @exec_results.concat(results)
  end

  def self.included(base)
    base.let(:runtime) { FakeRuntime.new }
    base.before do
      WarpEngine.config.local = WarpEngine::Local::Configuration.new.tap do |config|
        config.enabled = true
        config.runtime = runtime
        config.engine_url = "http://warp-engine-local:7470"
      end
    end
    base.after { WarpEngine.config.local = nil }
  end

  GITEA = "http://warp-local-gitea:3000/api/v1".freeze
  WOODPECKER = "http://warp-local-woodpecker:8000".freeze

  def stub_gitea_bootstrap(admin_exists: false)
    stub_request(:get, "http://warp-local-gitea:3000/api/healthz").to_return(status: 200)
    stub_request(:get, "#{GITEA}/user").to_return({ status: admin_exists ? 200 : 401, body: "{}" }, { status: 200, body: "{}" })
    stub_request(:get, "#{GITEA}/orgs/games").to_return(status: 404, body: "{}")
    stub_request(:post, "#{GITEA}/orgs").to_return(status: 201, body: "{}")
    stub_request(:post, "#{GITEA}/users/warp-admin/tokens").to_return(status: 201, body: { sha1: "gitea-token" }.to_json)
    stub_request(:get, "#{GITEA}/users/warp").to_return(status: 404, body: "{}")
    stub_request(:post, "#{GITEA}/admin/users").to_return(status: 201, body: "{}")
    stub_request(:patch, "#{GITEA}/admin/users/warp").to_return(status: 200, body: "{}")
    stub_request(:post, "#{GITEA}/users/warp/tokens").to_return(status: 201, body: { sha1: "push-token" }.to_json)
  end

  def ready_component(key, settings: {}, secrets: {})
    WarpEngine::LocalComponent.for(key).tap do |record|
      record.update!(state: "ready", settings: settings)
      record.secrets = secrets
      record.save!
    end
  end
end
