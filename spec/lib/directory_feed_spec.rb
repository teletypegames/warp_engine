require "rails_helper"

RSpec.describe WarpEngine::Feeds::Directory do
  let(:c64) { { key: "c64", type: "directory", platform: "c64", kind: "package", path: "directories/C64", extension: ".prg" } }

  def configure(*feeds)
    allow(WarpEngine.config).to receive(:feeds).and_return(feeds)
  end

  def directories = WarpEngine::Feeds.validate!.grep(described_class)

  describe "validation" do
    it "has no directories by default" do
      expect(WarpEngine::Configuration.new.feeds).to eq([])
      configure

      expect(directories).to eq([])
      expect(WarpEngine::Feeds).not_to be_any
    end

    it "reads a directory with its defaults, upcasing the extension" do
      configure(c64)

      directory = directories.first

      expect(directory).to have_attributes(platform: "c64", kinds: [ "package" ], layout: "flat", extension: ".PRG",
                                       name_length: 16, statuses: [], urls: [])
      expect(directory.directory).to eq(File.join(WarpEngine.config.file_container_path, "directories/C64"))
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

        expect { directories }.to raise_error(WarpEngine::ConfigurationError, /\Ac64: /)
      end
    end

    it "reads a folders directory of two kinds, with DOS-sized names and the urls it is served at" do
      configure({ key: "apps", type: "directory", platform: "dos", kind: %w[package win_x86], layout: "folders",
                  path: "directories/APPS", urls: [ "ftp://ftp.example/APPS", "http://archive.example/APPS" ] })

      directory = directories.first

      expect(directory).to have_attributes(kinds: %w[package win_x86], layout: "folders", extension: "", name_length: 8,
                                       urls: [ "ftp://ftp.example/APPS", "http://archive.example/APPS" ])
      expect(directory.folder_name_valid?("WEDOSW")).to be(true)
      expect(directory.folder_name_valid?("WEDOSWXYZ")).to be(false)
      expect(directory.folder_name_valid?("we-dos")).to be(false)
    end

    it "refuses an extension on a folders directory" do
      configure({ key: "apps", type: "directory", platform: "dos", kind: "package", layout: "folders", path: "directories/APPS",
                  extension: ".ZIP" })

      expect { directories }.to raise_error(WarpEngine::ConfigurationError, /no extension/)
    end

    it "takes a known preview format on a flat directory only" do
      configure(c64.merge(preview: "c64"))
      expect(directories.first.preview_renderer).to eq(described_class::Preview::C64)
      expect(directories.first.preview_name_for("ARIADNE.PRG")).to eq("ARIADNE.PVW")

      configure(c64.merge(preview: "amiga"))
      expect { directories }.to raise_error(WarpEngine::ConfigurationError, /unknown preview/)

      configure({ key: "apps", type: "directory", platform: "dos", kinds: %w[package], layout: "folders",
                  path: "directories/APPS", preview: "c64" })
      expect { directories }.to raise_error(WarpEngine::ConfigurationError, /no preview/)
    end

    it "refuses two directories in one folder" do
      configure(c64, c64.merge(key: "plus4", platform: "plus4"))

      expect { directories }.to raise_error(WarpEngine::ConfigurationError, /share the path/)
    end

    it "refuses a storage that is not the local filesystem" do
      configure(c64)
      allow(WarpEngine::Storage).to receive(:local?).and_return(false)

      expect { directories }.to raise_error(WarpEngine::ConfigurationError, /:local storage/)
    end
  end

  describe "#descriptor" do
    it "says what the directory holds and where it is served" do
      configure(c64.merge(urls: [ "http://archive.example/C64" ]))

      expect(directories.first.descriptor).to eq({ key: "c64", type: "directory", platforms: [ "c64" ], kinds: [ "package" ],
                                               layout: "flat", index: "INDEX.TXT", urls: [ "http://archive.example/C64" ] })
    end
  end

  describe WarpEngine::Names do
    it "keeps letters, digits and dashes, in capitals" do
      expect(described_class.normalize("thread_of ariadné!")).to eq("THREAD-OF-ARIADNE")
    end

    it "cuts a file name to fit with its extension and drops a trailing dash" do
      software = build(:software, name: "thread-of-ariadne", directory_name: nil)

      expect(described_class.file_name(software, length: 11, extension: ".PRG")).to eq("THREAD.PRG")
      expect(described_class.file_name(build(:software, name: "---"), length: 16)).to be_nil
    end
  end

  describe "directory_name on a software" do
    it "is stored in capitals and may be left empty" do
      software = create(:software, directory_name: " ariadne ")

      expect(software.directory_name).to eq("ARIADNE")
      expect(create(:software, directory_name: "").directory_name).to be_nil
    end

    it "refuses characters a directory cannot hold" do
      expect(build(:software, directory_name: "ARIADNE.PRG")).not_to be_valid
    end

    it "is unique within a platform only" do
      create(:software, platform: "c64", directory_name: "ARIADNE")

      expect(build(:software, platform: "c64", directory_name: "ARIADNE")).not_to be_valid
      expect(build(:software, platform: "plus4", directory_name: "ARIADNE")).to be_valid
    end
  end
end
