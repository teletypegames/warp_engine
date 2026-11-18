require "rails_helper"
require_relative "../../support/admin_api_helpers"
require_relative "../../support/sync_helpers"

RSpec.describe "Admin API sync", type: :request do
  include AdminApiHelpers
  include SyncHelpers
  include ActiveJob::TestHelper

  before { sync_config }

  it "adds a peer and never shows its secret" do
    api_post "/sync_peers", { label: "Other", transport: "http", transportOptions: { host: "https://other.example/warp" },
                              secret: "abcdefgh-secret", outboundEnabled: true }

    expect(response).to have_http_status(:created)
    expect(json["data"]).to include("label" => "Other", "secretPrefix" => "abcdefgh", "transport" => "http",
                                    "transportOptions" => { "host" => "https://other.example/warp" }, "outboundEnabled" => true)
    expect(response.body).not_to include("abcdefgh-secret")
    expect(WarpEngine::SyncPeer.last.secret).to eq("abcdefgh-secret")
  end

  it "keeps the token when an update leaves it out, and deletes softly" do
    server = sync_peer(label: "Other", host: "https://other.example", secret: "first")

    api_patch "/sync_peers/#{server.id}", { label: "Renamed", outboundEnabled: false }
    expect(json["data"]).to include("label" => "Renamed", "outboundEnabled" => false)
    expect(server.reload.secret).to eq("first")

    api_delete "/sync_peers/#{server.id}"
    expect(response).to have_http_status(:no_content)
    expect(server.reload.deleted_at).to be_present
  end

  it "queues the releases a server may be missing" do
    server = sync_peer(label: "Other", host: "https://other.example", secret: "x")
    create(:release, software: create(:software, name: "game", platform: "c64"), version: "1.0")

    api_post "/sync_peers/#{server.id}/push", {}

    expect(json["data"]).to include("queued" => 1)
    expect(enqueued_jobs.map { |job| job["job_class"] }).to include("WarpEngine::SyncPushJob")
  end

  it "previews and runs a full sync without the configured filters to every active server" do
    sync_config(denied_softwares: %w[game])
    sync_peer(label: "One", host: "https://one.example", secret: "x")
    sync_peer(label: "Two", host: "https://two.example", secret: "y")
    software = create(:software, name: "game", platform: "c64")
    %w[1.0 1.1].each { |version| create(:release, software: software, version: version) }

    api_post "/sync_peers/run", { all: true, dryRun: true }
    expect(json["data"]).to include("dryRun" => true, "queued" => 0, "releases" => [])

    api_post "/sync_peers/run", { all: true, filtered: false }
    expect(json["data"]).to include("dryRun" => false, "queued" => 4)
    expect(json["data"]["releases"].map { |release| release["version"] }).to eq(%w[1.0 1.1])
  end

  it "answers 400 to an unknown channel" do
    server = sync_peer(label: "Other", host: "https://other.example", secret: "x")

    api_post "/sync_peers/#{server.id}/push", { channels: %w[nightly] }

    expect(response).to have_http_status(:bad_request)
  end

  it "answers 409 to a push while sync is off" do
    sync_config(enabled: false)
    server = sync_peer(label: "Other", host: "https://other.example", secret: "x")

    api_post "/sync_peers/#{server.id}/push", {}

    expect(response).to have_http_status(:conflict)
  end

  it "refuses an outbound http peer without a host" do
    api_post "/sync_peers", { label: "Nowhere", secret: "x", outboundEnabled: true }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "issues an inbound token once and revokes the one before" do
    peer = WarpEngine::SyncPeer.create!(label: "Them", outbound_enabled: false, inbound_enabled: true)

    api_post "/sync_peers/#{peer.id}/inbound_token", {}
    first = json["data"]["plainToken"]
    expect(response).to have_http_status(:created)
    expect(WarpEngine::ApplicationToken.authenticate(first, required_scope: "sync").owner).to eq(peer)

    api_post "/sync_peers/#{peer.id}/inbound_token", {}
    expect(WarpEngine::ApplicationToken.authenticate(first)).to be_nil
    api_get "/sync_peers/#{peer.id}"
    expect(json["data"]["inboundTokenPrefix"]).to eq(peer.reload.inbound_token.token_prefix)
    expect(response.body).not_to include(first)
  end

  it "tells a software's sync state and events" do
    peer = sync_peer(label: "Other")
    software = create(:software, name: "game", platform: "c64")
    create(:release, software: software, version: "1.0")
    WarpEngine::SyncEvent.create!(direction: "outbound", status: "succeeded", sync_peer: peer, software: software,
                                  software_name: "game", version: "1.0")

    api_get "/softwares/#{software.id}/sync_status"
    expect(json["data"].first).to include("peer" => "Other", "direction" => "outbound", "reason" => nil)
    expect(json["data"].first["event"]).to include("status" => "succeeded")

    api_get "/softwares/#{software.id}/sync_events"
    expect(json["data"].map { |event| event["version"] }).to eq(%w[1.0])

    api_get "/sync_events", params: { softwareId: software.id }
    expect(json["data"].size).to eq(1)
  end

  it "lists the events" do
    WarpEngine::SyncEvent.create!(direction: "inbound", status: "succeeded", software_name: "game", version: "1.0")

    api_get "/sync_events", params: { direction: "inbound" }

    expect(json["data"].map { |event| event["softwareName"] }).to eq(%w[game])
  end

  it "issues a sync token through the token API only to a peer, and only for an unrestricted caller" do
    peer = WarpEngine::SyncPeer.create!(label: "Them", outbound_enabled: false)
    keeper = admin_token_with(%w[admin:read admin:write admin:tokens])
    api_post "/application_tokens", { name: "Other engine", scopes: %w[sync], ownerId: peer.id }, token: keeper
    expect(response).to have_http_status(:forbidden)

    boss = admin_token_with(%w[admin:read admin:write admin:tokens], unrestricted: true)
    api_post "/application_tokens", { name: "Other engine", scopes: %w[sync], ownerId: peer.id }, token: boss
    expect(response).to have_http_status(:created)
    expect(json["data"]).to include("unrestricted" => true, "ownerType" => "WarpEngine::SyncPeer", "ownerId" => peer.id)
  end
end
