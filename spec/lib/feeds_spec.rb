require "rails_helper"

RSpec.describe WarpEngine::Feeds do
  let(:c64_directory) { { key: "c64", type: "directory", platform: "c64", kind: "package", path: "directories/C64", extension: ".PRG" } }
  let(:assembly64) { { key: "assembly64", type: "assembly64", platforms: %w[c64], hosts: %w[a64.example.org] } }

  def configure(feeds: [], types: {})
    allow(WarpEngine.config).to receive_messages(feeds: feeds, feed_types: types)
  end

  it "always has the catalog API first, then the feeds in their order" do
    configure(feeds: [ c64_directory, assembly64 ])

    feeds = described_class.validate!

    expect(feeds.map { |feed| [ feed.key, feed.type ] })
      .to eq([ %w[wecp wecp], %w[c64 directory], %w[assembly64 assembly64] ])
    expect(feeds.map { |feed| feed.class.static? }).to eq([ false, true, false ])
    expect(feeds.map { |feed| feed.class.dynamic? }).to eq([ true, false, true ])
    expect(described_class["assembly64"].hosts).to eq(%w[a64.example.org])
  end

  it "draws the catalog API and the dynamic types once each" do
    mapper = double("mapper")
    allow(WarpEngine::Feeds::Wecp).to receive(:draw_routes)
    allow(WarpEngine::Feeds::Assembly64).to receive(:draw_routes)
    configure

    described_class.draw_routes(mapper)

    expect(WarpEngine::Feeds::Wecp).to have_received(:draw_routes).with(mapper).once
    expect(WarpEngine::Feeds::Assembly64).to have_received(:draw_routes).with(mapper).once
  end

  it "is not any? with only the catalog API" do
    configure

    expect(described_class).not_to be_any
    expect(described_class.validate!.map(&:key)).to eq(%w[wecp])
  end

  {
    "an unknown type"                => { key: "x", type: "gopher" },
    "a malformed key"                => { key: "Bad Key", type: "assembly64" },
    "an unknown platform"            => { key: "x", type: "assembly64", platforms: %w[amiga] },
    "an unknown kind"                => { key: "x", type: "assembly64", kinds: %w[floppy] },
    "an unknown Assembly64 category" => { key: "x", type: "assembly64", categories: { game: "warez" } },
    "a malformed repo"               => { key: "x", type: "assembly64", repo: "Not OK" },
    "an unknown option"              => { key: "x", type: "assembly64", colour: "blue" },
    "the catalog API as a type"      => { key: "x", type: "wecp" }
  }.each do |label, definition|
    it "rejects #{label}" do
      configure(feeds: [ definition ])

      expect { described_class.validate! }.to raise_error(WarpEngine::ConfigurationError)
    end
  end

  it "rejects two feeds with one key" do
    configure(feeds: [ assembly64, assembly64.merge(hosts: %w[other.example.org]) ])

    expect { described_class.validate! }.to raise_error(WarpEngine::ConfigurationError, /share the key/)
  end

  it "uses a type the host registered" do
    stub_const("AcmeFeed", Class.new(WarpEngine::Feeds::Base) do
      include WarpEngine::Feeds::Static
      def self.type_name = "acme"
      def platforms = %w[c64]
      def sync!(dry_run: false) = :synced
    end)
    configure(feeds: [ { key: "acme", type: "acme" } ], types: { "acme" => "AcmeFeed" })

    expect(described_class["acme"]).to be_a(AcmeFeed)
    expect(described_class.refresh(platform: "c64")).to eq([ :synced ])
    expect(described_class.refresh(platform: "dos")).to eq([])
  end

  it "refuses a dynamic type that draws no routes" do
    stub_const("MuteFeed", Class.new(WarpEngine::Feeds::Base) do
      include WarpEngine::Feeds::Dynamic
      def self.type_name = "mute"
    end)
    configure(feeds: [ { key: "mute", type: "mute" } ], types: { "mute" => "MuteFeed" })

    expect { described_class.validate! }.to raise_error(WarpEngine::ConfigurationError, /draws no routes/)
  end

  it "logs a feed that fails to refresh and goes on" do
    configure(feeds: [ c64_directory ])
    allow(WarpEngine::Feeds::Directory::Builder).to receive(:new).and_raise(Errno::EACCES)
    allow(Rails.logger).to receive(:error)

    expect(described_class.refresh(platform: "c64")).to eq([])
    expect(Rails.logger).to have_received(:error).with(/refresh c64/)
  end

  it "describes every feed for the service descriptor" do
    configure(feeds: [ c64_directory, assembly64 ])

    expect(described_class.descriptors).to eq([
      { key: "wecp", type: "wecp", platforms: [], version: WarpEngine::API_VERSION },
      { key: "c64", type: "directory", platforms: [ "c64" ], kinds: [ "package" ], layout: "flat",
        index: "INDEX.TXT", urls: [] },
      { key: "assembly64", type: "assembly64", platforms: [ "c64" ], hosts: [ "a64.example.org" ],
        path: "/leet/search", repo: "assembly64" }
    ])
  end

  describe "the configuration DSL" do
    let(:config) { WarpEngine::Configuration.new }

    it "defines a feed, replacing one with the same key, and takes a directory as a feed of the type directory" do
      WarpEngine::Configuration::DSL.apply(config) do
        feed :assembly64, type: :assembly64, hosts: %w[old.example.org]
        feed :assembly64, type: :assembly64, hosts: %w[a64.example.org]
        feed :c64, type: :directory, platform: "c64", kind: "package", path: "directories/OLD", extension: ".PRG"
        directory :c64, kind: "package", path: "directories/C64", extension: ".PRG"
        directory :dos, key: :apps, kind: "package", layout: "folders", path: "directories/APPS"
        register_feed_type :acme, "AcmeFeed"
      end

      expect(config.feeds).to eq([
        { key: "assembly64", type: "assembly64", hosts: %w[a64.example.org] },
        { key: "c64", type: "directory", platform: "c64", kind: "package", path: "directories/C64", extension: ".PRG" },
        { key: "apps", type: "directory", platform: "dos", kind: "package", layout: "folders", path: "directories/APPS" }
      ])
      expect(config.feed_types).to eq("acme" => "AcmeFeed")
    end
  end
end
