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

      expect(shelf.to_h).to include(platform: "c64", kinds: [ "cartridge" ], layout: "flat", extension: ".PRG",
                                    name_length: 16, statuses: [], urls: [])
      expect(shelf.directory).to eq(File.join(WarpEngine.config.file_container_path, "shelves/C64"))
    end

    {
      "an unknown platform"         => { platform: "amiga" },
      "an unknown kind"             => { kind: "floppy" },
      "an extension without a dot"  => { extension: "PRG" },
      "no room for a name"          => { name_length: 4 },
      "an absolute path"            => { path: "/srv/C64" },
      "a path out of the container" => { path: "../C64" },
      "an unknown key"              => { colour: "blue" },
      "an unknown layout"           => { layout: "tree" },
      "no kind"                     => { kind: [] },
      "a url without a scheme"      => { urls: [ "archive.example/C64" ] },
      "a url of another scheme"     => { urls: [ "gopher://archive.example/C64" ] }
    }.each do |description, change|
      it "refuses #{description}" do
        configure(c64.merge(change))

        expect { described_class.validate! }.to raise_error(described_class::ConfigurationError)
      end
    end

    it "reads a folders shelf of two kinds, with DOS-sized names and the urls it is served at" do
      configure({ platform: "dos", kind: %w[cartridge win_x86], layout: "folders", path: "shelves/APPS",
                  urls: [ "ftp://ftp.example/APPS", "http://archive.example/APPS" ] })

      shelf = described_class.validate!.first

      expect(shelf.to_h).to include(kinds: %w[cartridge win_x86], layout: "folders", extension: "", name_length: 8,
                                    urls: [ "ftp://ftp.example/APPS", "http://archive.example/APPS" ])
      expect(shelf.folder_name_valid?("DOSINSTW")).to be(true)
      expect(shelf.folder_name_valid?("DOSINSTWX")).to be(false)
      expect(shelf.folder_name_valid?("dosinst")).to be(false)
    end

    it "refuses an extension on a folders shelf" do
      configure({ platform: "dos", kind: "cartridge", layout: "folders", path: "shelves/APPS", extension: ".ZIP" })

      expect { described_class.validate! }.to raise_error(described_class::ConfigurationError, /no extension/)
    end

    it "takes a known preview format on a flat shelf only" do
      configure(c64.merge(preview: "c64"))
      expect(described_class.validate!.first.preview_renderer).to eq(WarpEngine::ShelfPreview::C64)
      expect(described_class.validate!.first.preview_name_for("ARIADNE.PRG")).to eq("ARIADNE.PVW")

      configure(c64.merge(preview: "amiga"))
      expect { described_class.validate! }.to raise_error(described_class::ConfigurationError, /unknown shelf preview/)

      configure({ platform: "dos", kinds: %w[cartridge], layout: "folders", path: "shelves/APPS", preview: "c64" })
      expect { described_class.validate! }.to raise_error(described_class::ConfigurationError, /no preview/)
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

  describe ".descriptors" do
    it "says what each shelf holds and where it is served, and nothing when the configuration is broken" do
      configure(c64.merge(urls: [ "http://archive.example/C64" ]))

      expect(described_class.descriptors).to eq([ { platform: "c64", kinds: [ "cartridge" ], layout: "flat",
                                                    index: "INDEX.TXT", urls: [ "http://archive.example/C64" ] } ])

      configure(c64.merge(platform: "amiga"))
      expect(described_class.descriptors).to eq([])
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
