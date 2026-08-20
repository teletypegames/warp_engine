require "rails_helper"
require "tmpdir"

RSpec.describe "Serving through the storage adapter" do
  let(:tmpdir) { Dir.mktmpdir }

  let(:signing_adapter) do
    Class.new do
      def file?(_relative) = true
      def directory?(_relative) = false

      def locate(relative, filename: nil, expires_in: nil)
        WarpEngine::Storage::Location.redirect("https://cdn.example/#{relative}?signed=1")
      end
    end.new
  end

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    WarpEngine::Storage.reset!
    File.write(File.join(tmpdir, "game-1.0.zip"), "zip")
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe WarpEngine::FileService do
    it "serves a local file (default adapter)" do
      allow(WarpEngine.config).to receive(:storage_adapter).and_return(:local)

      result = described_class.new.show(WarpEngine::FileShowInputDto.new(path: "game-1.0.zip"))

      expect(result.type).to eq(:file)
      expect(result.path).to eq(File.join(tmpdir, "game-1.0.zip"))
    end

    it "redirects a directory to its index.html" do
      allow(WarpEngine.config).to receive(:storage_adapter).and_return(:local)
      FileUtils.mkdir_p(File.join(tmpdir, "game-1.0"))
      File.write(File.join(tmpdir, "game-1.0", "index.html"), "<h1>hi</h1>")

      result = described_class.new.show(WarpEngine::FileShowInputDto.new(path: "game-1.0"))

      expect(result.type).to eq(:redirect)
      expect(result.url).to eq("/file/game-1.0/index.html")
    end

    it "hands back the adapter's redirect when storage is remote" do
      allow(WarpEngine.config).to receive(:storage_adapter).and_return(signing_adapter)

      result = described_class.new.show(WarpEngine::FileShowInputDto.new(path: "game-1.0.zip"))

      expect(result.type).to eq(:redirect)
      expect(result.url).to eq("https://cdn.example/game-1.0.zip?signed=1")
    end

    it "reports a missing file" do
      allow(WarpEngine.config).to receive(:storage_adapter).and_return(:local)

      result = described_class.new.show(WarpEngine::FileShowInputDto.new(path: "nope.zip"))

      expect(result.type).to eq(:not_found)
    end
  end

  describe WarpEngine::DownloadService do
    let(:args) { { ip: "127.0.0.1", user_agent: "rspec", referer: nil } }

    it "keeps returning an absolute path from #create (backward compatible)" do
      allow(WarpEngine.config).to receive(:storage_adapter).and_return(:local)

      path = described_class.new.create(path: "game-1.0.zip", **args)

      expect(path).to eq(File.join(tmpdir, "game-1.0.zip"))
      expect(WarpEngine::Download.count).to eq(1)
    end

    it "returns nil from #create for a missing file" do
      allow(WarpEngine.config).to receive(:storage_adapter).and_return(:local)

      expect(described_class.new.create(path: "nope.zip", **args)).to be_nil
      expect(WarpEngine::Download.count).to eq(0)
    end

    it "returns a location from #locate and logs the download" do
      allow(WarpEngine.config).to receive(:storage_adapter).and_return(signing_adapter)

      location = described_class.new.locate(path: "game-1.0.zip", **args)

      expect(location).to be_redirect
      expect(location.url).to include("signed=1")
      expect(WarpEngine::Download.count).to eq(1)
    end
  end
end
