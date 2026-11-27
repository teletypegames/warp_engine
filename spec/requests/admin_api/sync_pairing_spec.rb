require "rails_helper"
require_relative "../../support/admin_api_helpers"
require_relative "../../support/sync_helpers"

RSpec.describe "Admin API sync pairing", type: :request do
  include AdminApiHelpers
  include SyncHelpers

  let(:pair_token) { admin_token_with("sync:pair") }

  before { sync_config(inbound: { enabled: true, pairing: :anyone }) }

  it "pairs with a sync:pair token: an inbound-only peer of its own and its token, shown once" do
    api_post "/sync_pairings", { label: "laptop local" }, token: pair_token

    expect(response).to have_http_status(:created)
    peer = WarpEngine::SyncPeer.last
    expect(json["data"]).to include("id" => peer.id, "label" => "laptop local", "plainToken" => be_present)
    expect(peer).to have_attributes(inbound_enabled: true, outbound_enabled: false, created_by: admin_owner)
    expect(WarpEngine::ApplicationToken.authenticate(json["data"]["plainToken"], required_scope: "sync")).to eq(peer.inbound_token)

    api_get "/sync_pairings/#{peer.id}", token: pair_token
    expect(json["data"]["plainToken"]).to be_nil
  end

  it "shows, renames, re-issues and deletes only the caller's own peers" do
    mine = WarpEngine::SyncPeer.create!(label: "Mine", inbound_enabled: true, outbound_enabled: false, created_by: admin_owner)
    theirs = WarpEngine::SyncPeer.create!(label: "Theirs", inbound_enabled: true, outbound_enabled: false, created_by: create(:test_owner, name: "other"))
    WarpEngine::SyncPeer.create!(label: "Admin made", inbound_enabled: true, outbound_enabled: false)

    api_get "/sync_pairings", token: pair_token
    expect(json["data"].pluck("label")).to eq([ "Mine" ])

    api_get "/sync_pairings/#{theirs.id}", token: pair_token
    expect(response).to have_http_status(:not_found)

    api_patch "/sync_pairings/#{mine.id}", { label: "Renamed" }, token: pair_token
    expect(mine.reload.label).to eq("Renamed")

    api_post "/sync_pairings/#{mine.id}/token", {}, token: pair_token
    expect(response).to have_http_status(:created)
    first = mine.reload.inbound_token
    api_post "/sync_pairings/#{mine.id}/token", {}, token: pair_token
    expect(first.reload.deleted_at).to be_present

    api_delete "/sync_pairings/#{mine.id}", token: pair_token
    expect(mine.reload.deleted_at).to be_present
    expect(mine.inbound_token.reload.deleted_at).to be_present
  end

  it "does not let a sync:pair token near the sync peers resource" do
    api_get "/sync_peers", token: pair_token

    expect(response).to have_http_status(:forbidden)
  end

  it "refuses sync:pair while only administrators may pair, but lets admin:write pair" do
    sync_config(inbound: { enabled: true, pairing: :admin })

    api_post "/sync_pairings", { label: "laptop" }, token: pair_token
    expect(response).to have_http_status(:forbidden)

    api_post "/sync_pairings", { label: "laptop" }
    expect(response).to have_http_status(:created)
  end

  it "answers 409 while inbound sync is off" do
    sync_config(inbound: { enabled: false, pairing: :anyone })

    post "/api/admin/v2/sync_pairings", params: { label: "x" }.to_json,
                                        headers: auth(pair_token).merge("CONTENT_TYPE" => "application/json")

    expect(response).to have_http_status(:conflict)
  end

  it "keeps a peer's own channels, within the known ones" do
    api_post "/sync_peers", { label: "Remote", transportOptions: { host: "https://remote.example" }, secret: "s",
                              outboundEnabled: true, allowedChannels: %w[stable beta] }
    expect(json["data"]["allowedChannels"]).to eq(%w[stable beta])

    api_patch "/sync_peers/#{json['data']['id']}", { allowedChannels: %w[nightly] }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
