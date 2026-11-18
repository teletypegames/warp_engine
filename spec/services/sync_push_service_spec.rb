require "rails_helper"
require "webmock/rspec"
require "tmpdir"
require "zip"
require_relative "../support/sync_helpers"

RSpec.describe WarpEngine::SyncPushService do
  include SyncHelpers

  let(:tmpdir) { Dir.mktmpdir }
  let(:server) { sync_peer(label: "Other", host: "https://other.example/warp", secret: "other-token") }
  let(:software) { create(:software, name: "game", platform: "c64", status: "released") }
  let(:release) { create(:release, software: software, version: "1.0") }
  let(:folder) { File.join(tmpdir, "game", "1.0") }
  let(:uploads) { [] }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    sync_config
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "game-1.0.prg"), "prg")
    File.write(File.join(folder, "game-1.0-win-x64.zip"), "zip")
    File.write(File.join(folder, "game-1.0.metadata.json"), "{}")
    stub_request(:post, %r{\Ahttps://other.example/warp/build/upload\?}).to_return do |request|
      uploads << request.body.b[/filename="([^"]+)"/, 1]
      { status: 200, body: "{}" }
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  def stub_publish(status: 200, body: { published: true })
    stub_request(:post, %r{\Ahttps://other.example/warp/build/publish\?}).to_return(status: status, body: body.to_json)
  end

  it "uploads the files the CI uploaded, then publishes" do
    publish = stub_publish

    result = described_class.new.push(release, server)

    expect(result.status).to eq("succeeded")
    expect(uploads).to contain_exactly("game-1.0.prg", "game-1.0-win-x64.zip", "game-1.0.metadata.json")
    expect(publish).to have_been_requested
    expect(server.reload.last_synced_at).to be_present
    expect(WarpEngine::SyncEvent.last).to have_attributes(status: "succeeded", files_count: 3, step: "publish")
  end

  it "leaves out the kinds the lists deny, but never a required one" do
    sync_config(denied_kinds: %w[win_x64 cartridge])
    stub_publish

    described_class.new.push(release, server)

    expect(uploads).to contain_exactly("game-1.0.prg", "game-1.0.metadata.json")
  end

  it "zips an unpacked kind again when its zip is gone" do
    software.update!(platform: "ebitengine")
    FileUtils.mkdir_p(File.join(folder, "html"))
    File.write(File.join(folder, "html", "index.html"), "<html>")
    stub_publish

    described_class.new.push(release, server)

    expect(uploads).to include("game-1.0.html.zip")
  end

  it "sends the files of a renamed software under the names the other side expects" do
    FileUtils.rm_f(Dir.glob(File.join(folder, "*")))
    File.write(File.join(folder, "old-1.0.prg"), "prg")
    File.write(File.join(folder, "old-1.0.metadata.json"), "{}")
    WarpEngine::ReleaseAsset.create!(release: release, kind: "cartridge", path: File.join(folder, "old-1.0.prg"))
    stub_publish

    expect(described_class.new.push(release, server).status).to eq("succeeded")
    expect(uploads).to contain_exactly("game-1.0.prg", "game-1.0.metadata.json")
  end

  it "counts a newer version on the other side as skipped" do
    stub_publish(status: 409, body: { error: "game 1.0 is older than 1.1" })

    result = described_class.new.push(release, server)

    expect(result.status).to eq("skipped")
    expect(server.reload.last_error).to be_nil
  end

  it "stops at a refused upload and records it on the server" do
    WebMock.reset!
    stub_request(:post, %r{/build/upload}).to_return(status: 401, body: { error: "Unauthorized" }.to_json)

    result = described_class.new.push(release, server)

    expect(result.status).to eq("failed")
    expect(WarpEngine::SyncEvent.last).to have_attributes(status: "failed", http_status: 401, message: "Unauthorized")
    expect(server.reload.last_error).to include("upload:")
  end

  it "skips a release the filters hold back" do
    sync_config(denied_platforms: %w[c64])

    expect(described_class.new.push(release, server).status).to eq("skipped")
    expect(uploads).to be_empty
  end

  describe "skipping what the server has" do
    def stub_builds(status: 200, releases: {})
      stub_request(:get, "https://other.example/warp/api/softwares/game/builds")
        .to_return(status: status, body: { platform: "c64", releases: releases }.to_json)
    end

    it "sends nothing when the server has the version with every kind" do
      stub_builds(releases: { "1.0" => { actual: %w[cartridge win_x64], missing: [] } })

      result = described_class.new.push(release, server, skip_existing: true)

      expect(result).to have_attributes(status: "skipped", message: "already on the peer (cartridge, win_x64)")
      expect(uploads).to be_empty
    end

    it "sends it when the server lacks a kind this push brings" do
      stub_builds(releases: { "1.0" => { actual: %w[cartridge], missing: [] } })
      stub_publish

      expect(described_class.new.push(release, server, skip_existing: true).status).to eq("succeeded")
      expect(uploads).to include("game-1.0-win-x64.zip")
    end

    it "sends it when the server has another version or no such software" do
      stub_builds(releases: { "0.9" => { actual: %w[cartridge win_x64] } })
      stub_publish
      expect(described_class.new.push(release, server, skip_existing: true).status).to eq("succeeded")

      stub_builds(status: 404)
      expect(described_class.new.push(release, server, skip_existing: true).status).to eq("succeeded")
    end

    it "goes ahead when the question goes unanswered" do
      stub_request(:get, %r{/builds}).to_raise(Errno::ECONNREFUSED)
      stub_publish

      expect(described_class.new.push(release, server, skip_existing: true).status).to eq("succeeded")
    end

    it "does not ask without skip_existing" do
      stub_publish

      described_class.new.push(release, server)

      expect(a_request(:get, %r{/builds})).not_to have_been_made
    end
  end

  it "logs a server that does not answer and raises so the job tries again" do
    WebMock.reset!
    stub_request(:post, %r{/build/upload}).to_raise(Errno::ECONNREFUSED)

    expect { described_class.new.push(release, server) }.to raise_error(WarpEngine::Sync::Transport::Unreachable)
    expect(WarpEngine::SyncEvent.last).to have_attributes(status: "failed")
  end
end
