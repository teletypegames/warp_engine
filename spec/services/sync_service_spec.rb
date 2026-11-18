require "rails_helper"
require "webmock/rspec"
require_relative "../support/sync_helpers"

RSpec.describe WarpEngine::SyncService do
  include SyncHelpers
  include ActiveJob::TestHelper

  let!(:server) { WarpEngine::SyncServer.create!(label: "Other", host: "https://other.example", secret: "other-token") }
  let(:software) { create(:software, name: "game", platform: "c64") }

  before { sync_config }

  describe "#dispatch" do
    let(:release) { create(:release, software: software, version: "1.0") }

    it "queues a push to every active server" do
      WarpEngine::SyncServer.create!(label: "Off", host: "https://off.example", secret: "x", active: false)

      expect { described_class.new.dispatch(release) }.to have_enqueued_job(WarpEngine::SyncPushJob).exactly(:once)
    end

    it "does not push on what came by sync" do
      expect { described_class.new.dispatch(release, source: :sync) }.not_to have_enqueued_job
    end

    it "does nothing while sync is off" do
      sync_config(enabled: false)

      expect { described_class.new.dispatch(release) }.not_to have_enqueued_job
    end

    it "logs a held back release only when verbose" do
      sync_config(denied_softwares: %w[game])
      expect { described_class.new.dispatch(release) }.not_to change(WarpEngine::SyncEvent, :count)

      sync_config(denied_softwares: %w[game], events: :verbose)
      described_class.new.dispatch(release)
      expect(WarpEngine::SyncEvent.last).to have_attributes(status: "skipped", message: "game is in denied_softwares")
    end

    it "writes no event when the events are off" do
      sync_config(events: false)

      expect { described_class.new.dispatch(release) }.to have_enqueued_job(WarpEngine::SyncPushJob)
      expect(WarpEngine::SyncEvent.count).to eq(0)
    end
  end

  describe "#backfill" do
    before do
      %w[1.0 1.10 1.9 2.0-beta.1].each { |version| create(:release, software: software, version: version) }
    end

    it "queues the newest allowed release of every software" do
      result = described_class.new.backfill(server)

      expect(result.queued.map(&:version)).to eq(%w[1.10])
    end

    it "queues every allowed release, oldest first, with all" do
      result = described_class.new.backfill(server, all: true)

      expect(result.queued.map(&:version)).to eq(%w[1.0 1.9 1.10])
      expect(result.skipped).to contain_exactly(a_string_including("2.0-beta.1"))
    end

    it "refuses while sync is off" do
      sync_config(enabled: false)

      expect { described_class.new.backfill(server) }.to raise_error(described_class::DisabledError)
    end
  end

  describe "#check" do
    it "takes a 400 as an accepted token" do
      stub_request(:post, "https://other.example/build/upload").to_return(status: 400, headers: { "WarpEngine-Version" => "4.5.0" })

      expect(described_class.new.check(server)).to have_attributes(ok: true, version: "4.5.0")
    end

    it "takes a 401 as a refused token" do
      stub_request(:post, "https://other.example/build/upload").to_return(status: 401)

      expect(described_class.new.check(server)).to have_attributes(ok: false, message: a_string_including("sync scope"))
    end
  end

  it "prunes the old events" do
    WarpEngine::SyncEvent.create!(direction: "outbound", status: "succeeded", created_at: 100.days.ago)
    WarpEngine::SyncEvent.create!(direction: "outbound", status: "succeeded")

    expect(described_class.new.prune_events).to eq(1)
  end

  describe WarpEngine::SyncPushJob do
    it "marks the event skipped when the release is gone" do
      event = WarpEngine::SyncEvent.create!(direction: "outbound", status: "queued", sync_server: server)

      described_class.perform_now(0, server.id, event.id)

      expect(event.reload.status).to eq("skipped")
    end
  end
end
