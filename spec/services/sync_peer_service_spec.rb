require "rails_helper"

RSpec.describe WarpEngine::SyncPeerService do
  include ActiveJob::TestHelper

  let(:owner) { create(:test_owner, name: "pairer") }
  let(:service) { described_class.new }

  it "pairs an inbound-only peer and issues its token in one step" do
    paired = service.pair(label: "laptop", owner: owner)

    expect(paired.peer).to be_persisted
    expect(paired.peer).to have_attributes(inbound_enabled: true, outbound_enabled: false, transport: "http", created_by: owner)
    expect(paired.peer.inbound_token).to eq(paired.token)
    expect(paired.token.plain_token).to be_present
  end

  it "leaves nothing behind when the peer does not validate" do
    expect { service.pair(label: "", owner: owner) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(WarpEngine::SyncPeer.count).to eq(0)
    expect(WarpEngine::ApplicationToken.count).to eq(0)
  end

  it "removes a peer with its inbound token" do
    peer = service.pair(label: "laptop", owner: owner).peer

    service.remove(peer)

    expect(peer.reload.deleted_at).to be_present
    expect(peer.inbound_token.reload.deleted_at).to be_present
  end

  it "queues the pushes to a peer" do
    peer = WarpEngine::SyncPeer.create!(label: "Other", transport: "http", outbound_enabled: true,
                                        transport_options: { "host" => "https://other.example" }, secret: "x")

    expect { service.queue_push(peer, all: true) }.to have_enqueued_job(WarpEngine::SyncBackfillJob).with(peer.id, nil, true)
  end
end
