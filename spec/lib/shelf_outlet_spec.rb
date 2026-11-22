require "rails_helper"

RSpec.describe WarpEngine::Outlets::Shelf do
  let(:c64) { { key: "c64", type: "shelf", platform: "c64", kind: "cartridge", path: "shelves/C64", extension: ".prg" } }

  def configure(*outlets)
    allow(WarpEngine.config).to receive(:outlets).and_return(outlets)
  end

  def shelves = WarpEngine::Outlets.validate!.grep(described_class)

  describe "validation" do
    it "has no shelves by default" do
      expect(WarpEngine::Configuration.new.outlets).to eq([])
      configure

      expect(shelves).to eq([])
      expect(WarpEngine::Outlets).not_to be_any
    end

    it "reads a shelf with its defaults, upcasing the extension" do
      configure(c64)

      shelf = shelves.first

      expect(shelf).to have_attributes(platform: "c64", kinds: [ "cartridge" ], layout: "flat", extension: ".PRG",
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
      "a url of another scheme"     => { urls: [ "gopher://archive.example/C64" ] },
      "a name length that is no number" => { name_length: "long" }
    }.each do |description, change|
      it "refuses #{description}" do
        configure(c64.merge(change))

        expect { shelves }.to raise_error(WarpEngine::ConfigurationError, /\Ac64: /)
      end
    end

    it "reads a folders shelf of two kinds, with DOS-sized names and the urls it is served at" do
      configure({ key: "apps", type: "shelf", platform: "dos", kind: %w[cartridge win_x86], layout: "folders",
                  path: "shelves/APPS", urls: [ "ftp://ftp.example/APPS", "http://archive.example/APPS" ] })

      shelf = shelves.first

      expect(shelf).to have_attributes(kinds: %w[cartridge win_x86], layout: "folders", extension: "", name_length: 8,
                                       urls: [ "ftp://ftp.example/APPS", "http://archive.example/APPS" ])
      expect(shelf.folder_name_valid?("WEDOSW")).to be(true)
      expect(shelf.folder_name_valid?("WEDOSWXYZ")).to be(false)
      expect(shelf.folder_name_valid?("we-dos")).to be(false)
    end

    it "refuses an extension on a folders shelf" do
      configure({ key: "apps", type: "shelf", platform: "dos", kind: "cartridge", layout: "folders", path: "shelves/APPS",
                  extension: ".ZIP" })

      expect { shelves }.to raise_error(WarpEngine::ConfigurationError, /no extension/)
    end

    it "takes a known preview format on a flat shelf only" do
      configure(c64.merge(preview: "c64"))
      expect(shelves.first.preview_renderer).to eq(described_class::Preview::C64)
      expect(shelves.first.preview_name_for("ARIADNE.PRG")).to eq("ARIADNE.PVW")

      configure(c64.merge(preview: "amiga"))
      expect { shelves }.to raise_error(WarpEngine::ConfigurationError, /unknown preview/)

      configure({ key: "apps", type: "shelf", platform: "dos", kinds: %w[cartridge], layout: "folders",
                  path: "shelves/APPS", preview: "c64" })
      expect { shelves }.to raise_error(WarpEngine::ConfigurationError, /no preview/)
    end

    it "refuses two shelves in one folder" do
      configure(c64, c64.merge(key: "plus4", platform: "plus4"))

      expect { shelves }.to raise_error(WarpEngine::ConfigurationError, /share the path/)
    end

    it "refuses a storage that is not the local filesystem" do
      configure(c64)
      allow(WarpEngine::Storage).to receive(:local?).and_return(false)

      expect { shelves }.to raise_error(WarpEngine::ConfigurationError, /:local storage/)
    end
  end

  describe "#descriptor" do
    it "says what the shelf holds and where it is served" do
      configure(c64.merge(urls: [ "http://archive.example/C64" ]))

      expect(shelves.first.descriptor).to eq({ key: "c64", type: "shelf", platforms: [ "c64" ], kinds: [ "cartridge" ],
                                               layout: "flat", index: "INDEX.TXT", urls: [ "http://archive.example/C64" ] })
    end
  end

  describe WarpEngine::Names do
    it "keeps letters, digits and dashes, in capitals" do
      expect(described_class.normalize("thread_of ariadné!")).to eq("THREAD-OF-ARIADNE")
    end

    it "cuts a file name to fit with its extension and drops a trailing dash" do
      software = build(:software, name: "thread-of-ariadne", shelf_name: nil)

      expect(described_class.file_name(software, length: 11, extension: ".PRG")).to eq("THREAD.PRG")
      expect(described_class.file_name(build(:software, name: "---"), length: 16)).to be_nil
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
