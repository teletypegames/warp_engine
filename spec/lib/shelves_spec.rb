require "rails_helper"

RSpec.describe WarpEngine::Shelves do
  let(:c64) { { platform: "c64", kind: "cartridge", path: "shelves/C64", extension: ".prg" } }

  def configure(*shelves)
    allow(WarpEngine.config).to receive(:shelves).and_return(shelves)
  end

  describe ".validate!" do
    it "accepts no shelves, which is the default" do
      expect(WarpEngine::Configuration.new.shelves).to eq([])
      configure

      expect(described_class.validate!).to eq([])
      expect(described_class).not_to be_any
    end

    it "reads a shelf with its defaults, upcasing the extension" do
      configure(c64)

      shelf = described_class.validate!.first

      expect(shelf.to_h).to include(platform: "c64", kind: "cartridge", extension: ".PRG", name_length: 16, statuses: [])
      expect(shelf.directory).to eq(File.join(WarpEngine.config.file_container_path, "shelves/C64"))
    end

    {
      "an unknown platform"         => { platform: "amiga" },
      "an unknown kind"             => { kind: "floppy" },
      "an extension without a dot"  => { extension: "PRG" },
      "no room for a name"          => { name_length: 4 },
      "an absolute path"            => { path: "/srv/C64" },
      "a path out of the container" => { path: "../C64" },
      "an unknown key"              => { colour: "blue" }
    }.each do |description, change|
      it "refuses #{description}" do
        configure(c64.merge(change))

        expect { described_class.validate! }.to raise_error(described_class::ConfigurationError)
      end
    end

    it "refuses two shelves in one folder" do
      configure(c64, c64.merge(platform: "plus4"))

      expect { described_class.validate! }.to raise_error(described_class::ConfigurationError, /share the path/)
    end

    it "refuses a storage that is not the local filesystem" do
      configure(c64)
      allow(WarpEngine::Storage).to receive(:local?).and_return(false)

      expect { described_class.validate! }.to raise_error(described_class::ConfigurationError, /:local storage/)
    end
  end

  describe ".normalize_name" do
    it "keeps letters, digits and dashes, in capitals" do
      expect(described_class.normalize_name("thread_of ariadné!")).to eq("THREAD-OF-ARIADNE")
    end
  end

  describe "shelf_name on a software" do
    it "is stored in capitals and may be left empty" do
      software = create(:software, shelf_name: " ariadne ")

      expect(software.shelf_name).to eq("ARIADNE")
      expect(create(:software, shelf_name: "").shelf_name).to be_nil
    end

    it "refuses characters a shelf cannot hold" do
      expect(build(:software, shelf_name: "ARIADNE.PRG")).not_to be_valid
    end

    it "is unique within a platform only" do
      create(:software, platform: "c64", shelf_name: "ARIADNE")

      expect(build(:software, platform: "c64", shelf_name: "ARIADNE")).not_to be_valid
      expect(build(:software, platform: "plus4", shelf_name: "ARIADNE")).to be_valid
    end
  end
end
