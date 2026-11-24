require "rails_helper"
require_relative "../support/sync_helpers"

RSpec.describe "DELETE /build/release", type: :request do
  include SyncHelpers

  let(:them) { WarpEngine::SyncPeer.create!(label: "Them", outbound_enabled: false, inbound_enabled: true) }
  let(:other) { WarpEngine::SyncPeer.create!(label: "Other", outbound_enabled: false, inbound_enabled: true) }
  let(:sync_token) { them.issue_inbound_token! }
  let(:software) { create(:software, name: "game", platform: "tic80", status: "released") }

  before do
    allow(WarpEngine.config).to receive_messages(application_token_source: :database, application_token_owner_class: "TestOwner")
    sync_config(inbound: { enabled: true })
  end

  def remove(token: sync_token, **params)
    delete "/build/release", params: params, headers: { "X-Update-Secret" => token.plain_token }
    JSON.parse(response.body)
  end

  def pushed(version, by: them) = create(:release, software: software, version: version, origin: "sync", sync_peer_id: by.id)

  it "removes a release the peer pushed, and the software with its last one" do
    pushed("1.0")
    pushed("1.1")

    expect(remove(name: "game", version: "1.0")).to eq("removed" => %w[1.0], "software" => false)
    expect(software.releases.reload.map(&:version)).to eq(%w[1.1])

    expect(remove(name: "game", version: "1.1")).to eq("removed" => %w[1.1], "software" => true)
    expect(software.reload).to be_discarded
    expect(WarpEngine::SyncEvent.last).to have_attributes(direction: "inbound", step: "remove", status: "succeeded")
  end

  it "removes only the peer's own releases when the software goes" do
    pushed("1.0")
    local = create(:release, software: software, version: "2.0")
    pushed("3.0", by: other)

    expect(remove(name: "game")).to eq("removed" => %w[1.0], "software" => false)
    expect(software.releases.reload).to contain_exactly(local, WarpEngine::Release.find_by(version: "3.0"))
  end

  it "refuses what the peer did not push here, and answers 404 for what is not here" do
    create(:release, software: software, version: "2.0")

    remove(name: "game", version: "2.0")
    expect(response).to have_http_status(:conflict)

    remove(name: "game", version: "9.9")
    expect(response).to have_http_status(:not_found)

    remove(name: "nothing")
    expect(response).to have_http_status(:not_found)
  end

  it "needs a sync token of a peer that may push here" do
    pushed("1.0")
    them.update!(inbound_enabled: false)

    remove(name: "game", version: "1.0")

    expect(response).to have_http_status(:forbidden)
    expect(software.releases.reload.size).to eq(1)
  end
end
