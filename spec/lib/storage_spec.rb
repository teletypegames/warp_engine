require "rails_helper"
require "tmpdir"

RSpec.describe WarpEngine::Storage do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    WarpEngine::Storage.reset!
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe ".adapter" do
    it "defaults to the local filesystem" do
      allow(WarpEngine.config).to receive(:storage_adapter).and_return(:local)

      expect(described_class.adapter).to be_a(described_class::LocalAdapter)
      expect(described_class).to be_local
    end

    it "returns whatever object the host configured" do
      custom = Object.new
      allow(WarpEngine.config).to receive(:storage_adapter).and_return(custom)

      expect(described_class.adapter).to eq(custom)
      expect(described_class).not_to be_local
    end
  end

  describe described_class::LocalAdapter do
    subject(:adapter) { described_class.new }

    before { File.write(File.join(tmpdir, "game-1.0.zip"), "zip") }

    it "sees files and directories under the container" do
      FileUtils.mkdir_p(File.join(tmpdir, "game-1.0"))

      expect(adapter.file?("game-1.0.zip")).to be(true)
      expect(adapter.directory?("game-1.0")).to be(true)
      expect(adapter.file?("missing.zip")).to be(false)
    end

    # The path traversal guard has to survive the move behind the adapter.
    it "refuses paths escaping the container" do
      outside = File.join(Dir.mktmpdir, "secret.txt")
      File.write(outside, "nope")

      expect(adapter.file?("../#{File.basename(File.dirname(outside))}/secret.txt")).to be(false)
    end

    it "locates a file as an absolute path" do
      location = adapter.locate("game-1.0.zip")

      expect(location).to be_file
      expect(location.path).to eq(File.join(tmpdir, "game-1.0.zip"))
    end
  end
end
