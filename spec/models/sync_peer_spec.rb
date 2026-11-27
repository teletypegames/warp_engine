require "rails_helper"
require_relative "../support/sync_helpers"

RSpec.describe WarpEngine::SyncPeer do
  include SyncHelpers

  it "stores the secret encrypted and keeps its prefix" do
    peer = sync_peer(host: "https://other.example/warp/", secret: "abcdefgh12345678")

    expect(peer.reload.secret).to eq("abcdefgh12345678")
    expect(peer.read_attribute(:secret)).not_to include("abcdefgh12345678")
    expect(peer.secret_prefix).to eq("abcdefgh")
    expect(peer.target).to eq("https://other.example/warp/")
  end

  it "keeps the stored secret when an empty one is given" do
    peer = sync_peer(secret: "first-token")
    peer.update!(secret: "", label: "Renamed")

    expect(peer.reload.secret).to eq("first-token")
  end

  it "needs the options of its transport only while it takes outbound pushes" do
    expect(described_class.new(label: "Them", outbound_enabled: true)).not_to be_valid
    expect(described_class.new(label: "Them", outbound_enabled: true, transport_options: { "host" => "other.example" }, secret: "x"))
      .not_to be_valid
    expect(described_class.new(label: "Them", outbound_enabled: false)).to be_valid
  end

  it "refuses an unknown transport" do
    peer = described_class.new(label: "Them", transport: "carrier-pigeon", outbound_enabled: false)

    expect(peer).not_to be_valid
    expect(peer.errors[:transport].first).to include("http")
  end

  it "issues an inbound token it owns, revoking the one before" do
    peer = described_class.create!(label: "Them", outbound_enabled: false)
    first = peer.issue_inbound_token!
    second = peer.issue_inbound_token!

    expect(second).to have_attributes(owner: peer, scopes: %w[sync], unrestricted: true)
    expect(peer.reload.inbound_token).to eq(second)
    expect(first.reload.deleted_at).to be_present
  end

  it "accepts inbound pushes only while inbound sync and the peer allow it" do
    peer = described_class.create!(label: "Them", outbound_enabled: false, inbound_enabled: true)
    sync_config(inbound: { enabled: false })
    expect(peer.accepts_inbound?).to be(false)

    sync_config(inbound: { enabled: true })
    expect(peer.accepts_inbound?).to be(true)
    peer.update!(inbound_enabled: false)
    expect(peer.accepts_inbound?).to be(false)
  end
end

RSpec.describe WarpEngine::ApplicationToken, "sync scope" do
  before { allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner") }

  let(:peer) { WarpEngine::SyncPeer.create!(label: "Them", outbound_enabled: false) }

  it "belongs only to a sync peer" do
    expect(build(:application_token, scopes: [ "sync" ])).not_to be_valid
    expect(create(:application_token, scopes: [ "sync" ], owner: peer)).to be_unrestricted
  end

  it "refuses to make a sync token restricted again" do
    token = create(:application_token, scopes: [ "sync" ], owner: peer)
    token.unrestricted = false

    expect(token).not_to be_valid
  end

  it "authenticates with any of several scopes" do
    token = create(:application_token, scopes: [ "sync" ], owner: peer)

    expect(described_class.authenticate(token.plain_token, required_scope: %w[upload sync])).to eq(token)
    expect(described_class.authenticate(token.plain_token, required_scope: "upload")).to be_nil
  end

  it "is not written to any CI repository" do
    create(:ci_repository)
    token = create(:application_token, scopes: [ "sync" ], owner: peer)

    expect(WarpEngine::SecretSyncService.new(ci: WarpEngine.ci).repositories_for_token(token)).to be_empty
  end
end
