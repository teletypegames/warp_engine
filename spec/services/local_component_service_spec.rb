require "rails_helper"
require "webmock/rspec"
require_relative "../support/local_helpers"

RSpec.describe WarpEngine::LocalComponentService do
  include LocalHelpers
  include ActiveJob::TestHelper

  let(:operation) { WarpEngine::LocalOperation.create!(kind: "enable", target: "gitea") }

  it "lists the registered components, unavailable with the reason when there is no runtime" do
    expect(described_class.new.list.map { |line| [ line.key, line.role, line.state ] }).to eq([ %w[gitea forge off], %w[woodpecker ci off] ])

    WarpEngine.config.local.runtime = :null
    expect(described_class.new.list.first).to have_attributes(state: "unavailable", message: a_string_including("runtime"))
  end

  it "starts the git server on the network and sets it up with generated sign-ins" do
    stub_gitea_bootstrap

    record = described_class.new.enable("gitea", operation)

    expect(record.reload).to have_attributes(state: "ready")
    expect(runtime.calls).to include([ :network, "warp-local" ], [ :pull, "gitea/gitea:1.27.3" ], [ :run, "warp-local-gitea", "warp-local" ])
    expect(runtime.calls).to include([ :exec, "warp-local-gitea", %w[gitea admin user create], "git" ])
    expect(record.secrets).to include("token" => "gitea-token", "pusher_token" => "push-token", "admin_password" => a_string_matching(/\A\h{32}\z/))
    expect(operation.reload.steps.pluck("text")).to include("create the organisation games", "Git server (Gitea) is ready")
  end

  it "names the containers and volumes with the configured prefix" do
    WarpEngine.config.local.name_prefix = "warp-example"
    stub_request(:get, "http://warp-example-gitea:3000/api/healthz").to_return(status: 200)
    gitea = WarpEngine::LocalComponent.for("gitea").component

    expect(gitea.containers.map(&:name)).to eq([ "warp-example-gitea" ])
    expect(gitea.volumes).to eq([ "warp-example-gitea-data" ])
    expect(gitea.internal_url).to eq("http://warp-example-gitea:3000")
    expect(WarpEngine::LocalComponent.for("woodpecker").component.containers.map(&:name))
      .to eq(%w[warp-example-woodpecker warp-example-woodpecker-agent])
  end

  it "publishes the CI's web UI on a CI port and signs in through the public addresses" do
    WarpEngine.config.local.ci_port = 8000
    ready_component("gitea")
    woodpecker = WarpEngine::LocalComponent.for("woodpecker").component
    server = woodpecker.containers.first

    expect(server.ports).to eq(8000 => 8000)
    expect(server.env).to include("WOODPECKER_HOST" => "http://localhost:8000",
                                  "WOODPECKER_EXPERT_FORGE_OAUTH_HOST" => "http://localhost:7471",
                                  "WOODPECKER_EXPERT_WEBHOOK_HOST" => "http://warp-local-woodpecker:8000")
    expect(woodpecker.http.rewrite("http://localhost:8000/authorize?code=x")).to eq("http://warp-local-woodpecker:8000/authorize?code=x")
    expect(woodpecker.http.rewrite("http://localhost:7471/login/oauth/authorize")).to eq("http://warp-local-gitea:3000/login/oauth/authorize")
  end

  it "answers the forge seam with the ready git server" do
    ready_component("gitea", secrets: { "token" => "t" })

    expect(WarpEngine.forge).to be_a(WarpEngine::Forge::Gitea)
    expect(WarpEngine.forge.instance_variable_get(:@base_url)).to eq("http://warp-local-gitea:3000")

    WarpEngine.config.local.enabled = false
    expect(WarpEngine.forge).not_to be_a(WarpEngine::Forge::Gitea)
  end

  it "answers the CI seam with the configured Woodpecker adapter pointed at the local server" do
    ready_component("woodpecker", secrets: { "token" => "wp" })
    base = WarpEngine::CI::Woodpecker::Adapter.new(url: nil, api_token: nil, update_server: "http://localhost:7470")
    allow(WarpEngine.config).to receive(:ci_adapter).and_return(base)

    adapter = WarpEngine.ci

    expect(adapter.url).to eq("http://warp-local-woodpecker:8000")
    expect(adapter.update_server).to eq("http://warp-engine-local:7470")
    expect(adapter).to be_configured
  end

  it "enables the git server first for the CI, and fails the CI with the reason" do
    stub_gitea_bootstrap
    stub_request(:get, "#{LocalHelpers::GITEA}/user/applications/oauth2").to_return(status: 200, body: "[]")
    stub_request(:post, "#{LocalHelpers::GITEA}/user/applications/oauth2").to_return(status: 201, body: { client_id: "cid", client_secret: "cs" }.to_json)
    stub_request(:get, "#{LocalHelpers::WOODPECKER}/healthz").to_return(status: 200)
    allow_any_instance_of(WarpEngine::Local::Components::Woodpecker).to receive(:sign_in).and_return("wp-token")
    stub_request(:post, "#{LocalHelpers::WOODPECKER}/api/secrets").to_return(status: 500)
    stub_request(:patch, "#{LocalHelpers::WOODPECKER}/api/secrets/gitea_token").to_return(status: 500)

    expect { described_class.new.enable("woodpecker", operation) }.to raise_error(WarpEngine::Local::Error, /gitea_token/)
    expect(WarpEngine::LocalComponent.find_by(key: "gitea")).to be_ready
    expect(WarpEngine::LocalComponent.find_by(key: "woodpecker")).to have_attributes(state: "failed", last_error: a_string_including("gitea_token"))
    expect(runtime.calls).to include([ :run, "warp-local-woodpecker", "warp-local" ], [ :run, "warp-local-woodpecker-agent", "warp-local" ])
  end

  it "stops the CI with the git server, and purges both with their volumes and secrets" do
    ready_component("gitea")
    ready_component("woodpecker")

    described_class.new.disable("gitea", operation)
    expect(runtime.calls.select { |call| call.first == :stop }.map(&:last))
      .to eq(%w[warp-local-woodpecker-agent warp-local-woodpecker warp-local-gitea])
    expect(WarpEngine::LocalComponent.pluck(:state).uniq).to eq([ "stopped" ])

    described_class.new.remove("gitea", operation, purge: true)
    expect(runtime.calls).to include([ :remove_volume, "warp-local-gitea-data" ], [ :remove_volume, "warp-local-woodpecker-data" ])
    expect(WarpEngine::LocalComponent.count).to eq(0)
  end

  it "queues an operation and runs it to its end" do
    stub_gitea_bootstrap
    queued = described_class.new.queue("enable", "gitea")
    expect(WarpEngine::LocalOperationJob).to have_been_enqueued.with(queued.id)

    perform_enqueued_jobs
    expect(queued.reload).to have_attributes(state: "succeeded")
  end
end
