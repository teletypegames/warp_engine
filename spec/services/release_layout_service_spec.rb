require "rails_helper"
require "tmpdir"

RSpec.describe WarpEngine::ReleaseLayoutService do
  let(:container) { Dir.mktmpdir }
  let(:service) { described_class.new }

  before do
    allow(WarpEngine.config).to receive_messages(file_container_path: container, storage_adapter: :local)
    allow(WarpEngine::Outlets).to receive(:refresh)
    WarpEngine::Storage.reset!
  end

  after do
    FileUtils.rm_rf(container)
    WarpEngine::Storage.reset!
  end

  def write(relative, content = relative)
    path = File.join(container, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def release(name, version, platform: "c64")
    software = WarpEngine::Software.find_by(name: name) || create(:software, name: name, platform: platform)
    create(:release, software: software, version: version)
  end

  describe WarpEngine::ReleaseLayout do
    let(:releases) { described_class.owners([ %w[game 1], %w[game 1.0], %w[game-plus4 1.0] ]) }

    it "gives an entry to the longest name-version it starts with" do
      expect(described_class.legacy_parts("game-1.0.prg", releases)).to eq(%w[game 1.0 game-1.0.prg])
      expect(described_class.legacy_parts("game-1-win-x64.zip", releases)).to eq(%w[game 1 game-1-win-x64.zip])
      expect(described_class.legacy_parts("game-plus4-1.0.prg", releases)).to eq(%w[game-plus4 1.0 game-plus4-1.0.prg])
      expect(described_class.legacy_parts("game-2.0.prg", releases)).to be_nil
    end

    it "names an unpacked folder after its kind" do
      expect(described_class.legacy_parts("game-1.0", releases)).to eq(%w[game 1.0 html])
      expect(described_class.legacy_parts("game-1.0-docs", releases)).to eq(%w[game 1.0 docs])
    end

    it "takes a renamed software's prefix from its assets" do
      owners = described_class.owners([ %w[rabbitc64 1.0.0] ], "rabbit-1.0.0-win-x64.zip" => %w[rabbitc64 1.0.0],
                                                               "rabbit-1.0.0" => %w[rabbitc64 1.0.0])

      expect(owners.keys).to contain_exactly("rabbitc64-1.0.0", "rabbit-1.0.0")
      expect(described_class.legacy_parts("rabbit-1.0.0.metadata.json", owners)).to eq(%w[rabbitc64 1.0.0 rabbit-1.0.0.metadata.json])
      expect(described_class.legacy_prefix("labyrintwo-1.1.prg")).to eq("labyrintwo-1.1")
      expect(described_class.legacy_prefix("game-1.0-docs")).to eq("game-1.0")
    end

    it "reserves the runtimes and the shelf roots" do
      allow(WarpEngine.config).to receive(:outlets).and_return([ { key: "c64", type: "shelf", platform: "c64", kind: "cartridge", path: "shelves/C64", extension: ".PRG", name_length: 16 } ])

      expect(described_class.reserved).to eq(%w[_runtimes shelves])
    end
  end

  describe "#restructure" do
    it "moves every release's entries into its folder and repoints the records" do
      game = release("game", "1.0")
      prg = write("game-1.0.prg")
      write("game-1.0.metadata.json")
      write("game-1.0/index.html", "<h1>hi</h1>")
      write("game-1.0.html.zip")
      WarpEngine::ReleaseAsset.create!(release: game, kind: "cartridge", path: prg)
      WarpEngine::ReleaseAsset.create!(release: game, kind: "html", path: File.join(container, "game-1.0"))
      WarpEngine::Download.create!(file_path: "game-1.0.prg", release: game, ip_address: "127.0.0.1")
      WarpEngine::Download.create!(file_path: "game-1.0/index.html", release: game, ip_address: "127.0.0.1")
      write("_runtimes/emulatorjs-4.2.3/loader.js")
      write("stray-0.1.prg")

      report = service.restructure(dry_run: false)

      expect(report.count).to eq(4)
      expect(report.lines).to include("stray-0.1.prg: left, no release owns it", "game-1.0 -> game/1.0/html")
      expect(Dir.children(container).sort).to eq(%w[_runtimes game stray-0.1.prg])
      expect(Dir.children(File.join(container, "game", "1.0")).sort)
        .to eq(%w[game-1.0.html.zip game-1.0.metadata.json game-1.0.prg html])
      expect(game.release_assets.reload.pluck(:kind, :path)).to contain_exactly(
        [ "cartridge", File.join(container, "game/1.0/game-1.0.prg") ], [ "html", File.join(container, "game/1.0/html") ]
      )
      expect(WarpEngine::Download.where(release: game).pluck(:file_path))
        .to contain_exactly("game/1.0/game-1.0.prg", "game/1.0/html/index.html")
      expect(WarpEngine::Outlets).to have_received(:refresh)
    end

    it "moves a renamed software's files with its release" do
      rabbit = release("rabbitc64", "1.0.0")
      prg = write("rabbit-1.0.0.prg")
      write("rabbit-1.0.0.metadata.json")
      WarpEngine::ReleaseAsset.create!(release: rabbit, kind: "cartridge", path: prg)

      service.restructure(dry_run: false)

      expect(Dir.children(File.join(container, "rabbitc64", "1.0.0")).sort).to eq(%w[rabbit-1.0.0.metadata.json rabbit-1.0.0.prg])
      expect(rabbit.release_assets.reload.pluck(:path)).to eq([ File.join(container, "rabbitc64/1.0.0/rabbit-1.0.0.prg") ])
      expect(described_class.new.relocate("rabbit-1.0.0.prg")).to eq("rabbitc64/1.0.0/rabbit-1.0.0.prg")
    end

    it "only lists on a dry run, and leaves an entry whose target exists" do
      release("game", "1.0")
      write("game-1.0.prg", "old")
      write("game/1.0/game-1.0.prg", "new")

      report = service.restructure(dry_run: true)

      expect(report.lines).to eq([ "game-1.0.prg: left, game/1.0/game-1.0.prg exists" ])
      expect(File.read(File.join(container, "game-1.0.prg"))).to eq("old")
    end

    it "is a no-op once the container is restructured" do
      release("game", "1.0")
      write("game-1.0.prg")
      service.restructure(dry_run: false)

      expect(described_class.new.restructure(dry_run: false).count).to eq(0)
    end
  end

  describe "#relocate" do
    before do
      release("game", "1.0")
      write("game/1.0/game-1.0.prg")
      write("game/1.0/html/index.html")
    end

    it "finds where a flat path went" do
      expect(service.relocate("game-1.0.prg")).to eq("game/1.0/game-1.0.prg")
      expect(service.relocate("game-1.0/index.html")).to eq("game/1.0/html/index.html")
      expect(service.relocate("game-1.0")).to eq("game/1.0/html")
    end

    it "answers nil for what no release owns or is not there" do
      expect(service.relocate("game-1.0.zip")).to be_nil
      expect(service.relocate("other-1.0.prg")).to be_nil
      expect(service.relocate("game")).to be_nil
    end
  end

  describe "the old URLs", type: :request do
    before do
      release("game", "1.0")
      write("game/1.0/game-1.0.prg", "prg")
      write("game/1.0/html/index.html", "<h1>hi</h1>")
    end

    it "redirects a flat file path and folder to where they moved" do
      get "/file/game-1.0.prg"
      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/file/game/1.0/game-1.0.prg")

      get "/file/game-1.0/"
      expect(response.location).to end_with("/file/game/1.0/html")
    end

    it "serves a download of a flat path from its new place and logs that" do
      location = WarpEngine::DownloadService.new.locate(path: "game-1.0.prg", ip: "127.0.0.1", user_agent: "spec", referer: nil)

      expect(location.path).to eq(File.join(container, "game/1.0/game-1.0.prg"))
      expect(WarpEngine::Download.last.file_path).to eq("game/1.0/game-1.0.prg")
    end
  end
end
