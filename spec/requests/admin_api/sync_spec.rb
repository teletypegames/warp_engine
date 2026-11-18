require "rails_helper"
require_relative "../../support/admin_api_helpers"
require_relative "../../support/sync_helpers"

RSpec.describe "Admin API sync", type: :request do
  include AdminApiHelpers
  include SyncHelpers
  include ActiveJob::TestHelper

  before { sync_config }

  it "adds a server and never shows its token" do
    api_post "/sync_servers", { label: "Other", host: "https://other.example/warp", secret: "abcdefgh-secret" }

    expect(response).to have_http_status(:created)
    expect(json["data"]).to include("label" => "Other", "secretPrefix" => "abcdefgh")
    expect(response.body).not_to include("abcdefgh-secret")
    expect(WarpEngine::SyncServer.last.secret).to eq("abcdefgh-secret")
  end

  it "keeps the token when an update leaves it out, and deletes softly" do
    server = WarpEngine::SyncServer.create!(label: "Other", host: "https://other.example", secret: "first")

    api_patch "/sync_servers/#{server.id}", { label: "Renamed", active: false }
    expect(json["data"]).to include("label" => "Renamed", "active" => false)
    expect(server.reload.secret).to eq("first")

    api_delete "/sync_servers/#{server.id}"
    expect(response).to have_http_status(:no_content)
    expect(server.reload.deleted_at).to be_present
  end

  it "queues the releases a server may be missing" do
    server = WarpEngine::SyncServer.create!(label: "Other", host: "https://other.example", secret: "x")
    create(:release, software: create(:software, name: "game", platform: "c64"), version: "1.0")

    api_post "/sync_servers/#{server.id}/push", {}

    expect(json["data"]).to include("queued" => 1)
    expect(enqueued_jobs.map { |job| job["job_class"] }).to include("WarpEngine::SyncPushJob")
  end

  it "previews and runs a full sync without the configured filters to every active server" do
    sync_config(denied_softwares: %w[game])
    WarpEngine::SyncServer.create!(label: "One", host: "https://one.example", secret: "x")
    WarpEngine::SyncServer.create!(label: "Two", host: "https://two.example", secret: "y")
    software = create(:software, name: "game", platform: "c64")
    %w[1.0 1.1].each { |version| create(:release, software: software, version: version) }

    api_post "/sync_servers/run", { all: true, dryRun: true }
    expect(json["data"]).to include("dryRun" => true, "queued" => 0, "releases" => [])

    api_post "/sync_servers/run", { all: true, filtered: false }
    expect(json["data"]).to include("dryRun" => false, "queued" => 4)
    expect(json["data"]["releases"].map { |release| release["version"] }).to eq(%w[1.0 1.1])
  end

  it "answers 400 to an unknown channel" do
    server = WarpEngine::SyncServer.create!(label: "Other", host: "https://other.example", secret: "x")

    api_post "/sync_servers/#{server.id}/push", { channels: %w[nightly] }

    expect(response).to have_http_status(:bad_request)
  end

  it "answers 409 to a push while sync is off" do
    sync_config(enabled: false)
    server = WarpEngine::SyncServer.create!(label: "Other", host: "https://other.example", secret: "x")

    api_post "/sync_servers/#{server.id}/push", {}

    expect(response).to have_http_status(:conflict)
  end

  it "lists the events" do
    WarpEngine::SyncEvent.create!(direction: "inbound", status: "succeeded", software_name: "game", version: "1.0")

    api_get "/sync_events", params: { direction: "inbound" }

    expect(json["data"].map { |event| event["softwareName"] }).to eq(%w[game])
  end

  it "makes an issued sync token unrestricted, so only an unrestricted caller issues one" do
    keeper = admin_token_with(%w[admin:read admin:write admin:tokens])
    api_post "/application_tokens", { name: "Other engine", scopes: %w[sync] }, token: keeper
    expect(response).to have_http_status(:forbidden)

    boss = admin_token_with(%w[admin:read admin:write admin:tokens], unrestricted: true)
    api_post "/application_tokens", { name: "Other engine", scopes: %w[sync] }, token: boss
    expect(response).to have_http_status(:created)
    expect(json["data"]).to include("unrestricted" => true)
  end
end
