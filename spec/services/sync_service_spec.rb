require "rails_helper"
require "webmock/rspec"
require "tmpdir"
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

      expect(result.releases.map(&:version)).to eq(%w[1.10])
    end

    it "queues every allowed release, oldest first, with all" do
      result = described_class.new.backfill(server, all: true)

      expect(result.releases.map(&:version)).to eq(%w[1.0 1.9 1.10])
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

  describe WarpEngine::SyncPushJob, "with criteria" do
    it "hands the filter and skip_existing to the push" do
      release = create(:release, software: software, version: "3.0")
      service = instance_double(WarpEngine::SyncPushService, push: nil)
      allow(WarpEngine::SyncPushService).to receive(:new).and_return(service)

      described_class.perform_now(release.id, server.id, nil, WarpEngine::Sync::Criteria.build(filtered: false).to_h.transform_keys(&:to_s))

      expect(service).to have_received(:push).with(release, server, hash_including(skip_existing: true, filter: an_instance_of(WarpEngine::Sync::Filter)))
    end
  end

  describe WarpEngine::SyncPushJob do
    it "marks the event skipped when the release is gone" do
      event = WarpEngine::SyncEvent.create!(direction: "outbound", status: "queued", sync_server: server)

      described_class.perform_now(0, server.id, event.id)

      expect(event.reload.status).to eq("skipped")
    end
  end
end

RSpec.describe WarpEngine::SyncService, "runs" do
  include SyncHelpers
  include ActiveJob::TestHelper

  let!(:server) { WarpEngine::SyncServer.create!(label: "Other", host: "https://other.example", secret: "other-token") }
  let!(:second) { WarpEngine::SyncServer.create!(label: "Second", host: "https://second.example", secret: "x") }
  let(:game) { create(:software, name: "game", platform: "c64", category: "game", status: "released") }
  let(:tool) { create(:software, name: "tool-x", platform: "dos", category: "tool", status: "development") }

  before do
    sync_config(denied_categories: %w[tool])
    %w[1.0 1.1 2.0-beta.1].each { |version| create(:release, software: game, version: version) }
    %w[0.1 0.2].each { |version| create(:release, software: tool, version: version) }
  end

  def criteria(**options) = WarpEngine::Sync::Criteria.build(**options)

  it "plans the newest release through the configured filters" do
    plan = described_class.new.plan(criteria)

    expect(plan.releases.map { |release| [ release.software.name, release.version ] }).to eq([ %w[game 1.1] ])
    expect(plan.skipped).to include("tool-x: tool is in denied_categories")
  end

  it "plans everything without the configured filters, the chosen channels only" do
    plan = described_class.new.plan(criteria(mode: "all", filtered: false, channels: %w[stable beta]))

    expect(plan.releases.map(&:version)).to eq(%w[1.0 1.1 2.0-beta.1 0.1 0.2])
  end

  it "narrows by software, platform, category and status" do
    plan = described_class.new.plan(criteria(mode: "all", filtered: false, platforms: %w[dos]))
    expect(plan.releases.map(&:version)).to eq(%w[0.1 0.2])

    plan = described_class.new.plan(criteria(filtered: false, softwares: "game, other-*", statuses: "released"))
    expect(plan.releases.map(&:version)).to eq(%w[1.1])
  end

  it "queues every planned release to every chosen server, carrying the criteria" do
    run_criteria = criteria(mode: "all", filtered: false)
    result = nil

    expect { result = described_class.new.run(run_criteria, servers: [ server, second ]) }
      .to have_enqueued_job(WarpEngine::SyncPushJob).exactly(8).times
    expect(result.queued).to eq(8)
    job = enqueued_jobs.last
    expect(job["arguments"].last).to include("filtered" => false, "mode" => "all", "skip_existing" => true)
  end

  it "leaves out an inactive server" do
    second.update!(active: false)

    expect(described_class.new.run(criteria, servers: [ server, second ]).servers).to eq([ server ])
  end

  it "pushes an unfiltered release whatever the configured lists say" do
    release = tool.releases.find_by(version: "0.2")
    stub_request(:post, %r{/build/upload}).to_return(status: 200, body: "{}")
    stub_request(:post, %r{/build/publish}).to_return(status: 200, body: "{}")
    Dir.mktmpdir do |dir|
      allow(WarpEngine.config).to receive(:file_container_path).and_return(dir)
      FileUtils.mkdir_p(File.join(dir, "tool-x", "0.2"))
      File.write(File.join(dir, "tool-x", "0.2", "tool-x-0.2.zip"), "x")

      expect(WarpEngine::SyncPushService.new.push(release, server).status).to eq("skipped")

      filter = criteria(filtered: false).filter
      expect(WarpEngine::SyncPushService.new.push(release, server, filter: filter).status).not_to eq("skipped")
    end
  end
end

RSpec.describe WarpEngine::Sync::Criteria do
  include SyncHelpers

  before { sync_config(allowed_channels: %w[stable beta]) }

  it "defaults to the newest release, the configured filters and channels" do
    criteria = described_class.build

    expect(criteria).to have_attributes(mode: "latest", filtered: true, channels: %w[stable beta], skip_existing: true)
    expect(described_class.build(skip_existing: "0").skip_existing).to be(false)
    expect(described_class.from_h("mode" => "all").skip_existing).to be(true)
  end

  it "reads loose values and travels as a Hash" do
    criteria = described_class.build(mode: "all", filtered: "0", channels: "dev", softwares: "a, b c", platforms: [ "c64", "" ])

    expect(criteria).to have_attributes(filtered: false, channels: %w[dev], softwares: %w[a b c], platforms: %w[c64])
    expect(described_class.from_h(criteria.to_h.transform_keys(&:to_s))).to eq(criteria)
    expect(criteria.summary).to include("every release", "no configured filters", "softwares: a, b, c")
  end

  it "refuses an unknown channel" do
    expect { described_class.build(channels: "nightly") }.to raise_error(ArgumentError, /nightly/)
  end
end

RSpec.describe WarpEngine::SyncRunnerForm do
  include SyncHelpers

  before { sync_config }

  let!(:server) { WarpEngine::SyncServer.create!(label: "Other", host: "https://other.example", secret: "x") }

  it "chooses every active server and the defaults before it is sent" do
    form = described_class.new({})

    expect(form.servers).to eq([ server ])
    expect(form.criteria).to have_attributes(mode: "latest", filtered: true, channels: %w[stable])
  end

  it "reads a sent form" do
    form = described_class.new("mode" => "all", "filtered" => "0", "channels" => %w[stable dev], "server_ids" => [],
                               "platforms" => %w[c64])

    expect(form.servers).to be_empty
    expect(form.criteria).to have_attributes(mode: "all", filtered: false, channels: %w[stable dev], platforms: %w[c64])
    expect(form.to_params).to include(mode: "all", filtered: "0", platforms: %w[c64])
  end

  it "needs a channel once sent" do
    expect { described_class.new("mode" => "latest").criteria }.to raise_error(ArgumentError, /channel/)
  end
end
