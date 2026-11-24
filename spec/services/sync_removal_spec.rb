require "rails_helper"
require "webmock/rspec"
require_relative "../support/sync_helpers"

RSpec.describe "Sync: removals" do
  include SyncHelpers
  include ActiveJob::TestHelper

  let!(:server) { sync_peer(label: "Other", host: "https://other.example/warp", secret: "other-token") }
  let(:software) { create(:software, name: "game", platform: "c64", status: "released") }

  before { sync_config(allowed_channels: WarpEngine::Channels::ALL) }

  it "queues the removal of a deleted release to the peers that would have got it" do
    release = create(:release, software: software, version: "1.0")

    expect { release.soft_delete! }.to have_enqueued_job(WarpEngine::SyncRemovalJob).with(server.id, "game", "1.0", anything)
    expect(WarpEngine::SyncEvent.last).to have_attributes(direction: "outbound", step: "remove", status: "queued", version: "1.0")
  end

  it "queues the removal of a deleted software without a version" do
    create(:release, software: software, version: "1.0")

    expect { software.soft_delete! }.to have_enqueued_job(WarpEngine::SyncRemovalJob).with(server.id, "game", nil, anything)
  end

  it "passes on no removal of what came by sync, nor to a peer the filters keep it from" do
    synced = create(:release, software: software, version: "1.0", origin: "sync", sync_peer_id: server.id)
    expect { synced.soft_delete! }.not_to have_enqueued_job(WarpEngine::SyncRemovalJob)

    server.update!(allowed_channels: %w[stable])
    beta = create(:release, software: software, version: "2.0.0-beta.1")
    expect { beta.soft_delete! }.not_to have_enqueued_job(WarpEngine::SyncRemovalJob)
  end

  it "asks the other engine to remove it, and takes a 404 as skipped" do
    removal = stub_request(:delete, "https://other.example/warp/build/release?name=game&version=1.0")
              .with(headers: { "X-Update-Secret" => "other-token" })
              .to_return(status: 200, body: { removed: %w[1.0], software: false }.to_json)

    expect(WarpEngine::SyncPushService.new.push_removal(server, name: "game", version: "1.0").status).to eq("succeeded")
    expect(removal).to have_been_requested.once

    stub_request(:delete, "https://other.example/warp/build/release?name=gone")
      .to_return(status: 404, body: { error: "no such software here" }.to_json)
    expect(WarpEngine::SyncPushService.new.push_removal(server, name: "gone").status).to eq("skipped")
  end

  it "skips a transport that carries no removals" do
    mirror = WarpEngine::SyncPeer.create!(label: "Mirror", transport: "rsync", outbound_enabled: true,
                                          transport_options: { "host" => "mirror.example", "user" => "warp", "path" => "/srv/warp" },
                                          secret: "key")

    result = WarpEngine::SyncPushService.new.push_removal(mirror, name: "game", version: "1.0")

    expect(result).to have_attributes(status: "skipped", message: "the rsync transport carries no removals")
  end
end
