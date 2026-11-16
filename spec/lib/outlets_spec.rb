require "rails_helper"

RSpec.describe WarpEngine::Outlets do
  let(:c64_shelf) { { key: "c64", type: "shelf", platform: "c64", kind: "cartridge", path: "shelves/C64", extension: ".PRG" } }
  let(:assembly64) { { key: "assembly64", type: "assembly64", platforms: %w[c64], hosts: %w[a64.example.org] } }

  def configure(outlets: [], types: {})
    allow(WarpEngine.config).to receive_messages(outlets: outlets, outlet_types: types)
  end

  it "always has the catalog API first, then the outlets in their order" do
    configure(outlets: [ c64_shelf, assembly64 ])

    outlets = described_class.validate!

    expect(outlets.map { |outlet| [ outlet.key, outlet.type ] })
      .to eq([ %w[wecp wecp], %w[c64 shelf], %w[assembly64 assembly64] ])
    expect(outlets.map { |outlet| outlet.class.materialized? }).to eq([ false, true, false ])
    expect(outlets.map { |outlet| outlet.class.served? }).to eq([ true, false, true ])
    expect(described_class["assembly64"].hosts).to eq(%w[a64.example.org])
  end

  it "draws the catalog API and the served types once each" do
    mapper = double("mapper")
    allow(WarpEngine::Outlets::Wecp).to receive(:draw_routes)
    allow(WarpEngine::Outlets::Assembly64).to receive(:draw_routes)
    configure

    described_class.draw_routes(mapper)

    expect(WarpEngine::Outlets::Wecp).to have_received(:draw_routes).with(mapper).once
    expect(WarpEngine::Outlets::Assembly64).to have_received(:draw_routes).with(mapper).once
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
      configure(outlets: [ definition ])

      expect { described_class.validate! }.to raise_error(WarpEngine::ConfigurationError)
    end
  end

  it "rejects two outlets with one key" do
    configure(outlets: [ assembly64, assembly64.merge(hosts: %w[other.example.org]) ])

    expect { described_class.validate! }.to raise_error(WarpEngine::ConfigurationError, /share the key/)
  end

  it "uses a type the host registered" do
    stub_const("AcmeOutlet", Class.new(WarpEngine::Outlets::Base) do
      include WarpEngine::Outlets::Materialized
      def self.type_name = "acme"
      def platforms = %w[c64]
      def sync!(dry_run: false) = :synced
    end)
    configure(outlets: [ { key: "acme", type: "acme" } ], types: { "acme" => "AcmeOutlet" })

    expect(described_class["acme"]).to be_a(AcmeOutlet)
    expect(described_class.refresh(platform: "c64")).to eq([ :synced ])
    expect(described_class.refresh(platform: "dos")).to eq([])
  end

  it "refuses a served type that draws no routes" do
    stub_const("MuteOutlet", Class.new(WarpEngine::Outlets::Base) do
      include WarpEngine::Outlets::Served
      def self.type_name = "mute"
    end)
    configure(outlets: [ { key: "mute", type: "mute" } ], types: { "mute" => "MuteOutlet" })

    expect { described_class.validate! }.to raise_error(WarpEngine::ConfigurationError, /draws no routes/)
  end

  it "logs an outlet that fails to refresh and goes on" do
    configure(outlets: [ c64_shelf ])
    allow(WarpEngine::Outlets::Shelf::Builder).to receive(:new).and_raise(Errno::EACCES)
    allow(Rails.logger).to receive(:error)

    expect(described_class.refresh(platform: "c64")).to eq([])
    expect(Rails.logger).to have_received(:error).with(/refresh c64/)
  end

  it "describes every outlet for the service descriptor" do
    configure(outlets: [ c64_shelf, assembly64 ])

    expect(described_class.descriptors).to eq([
      { key: "wecp", type: "wecp", platforms: [], version: WarpEngine::API_VERSION },
      { key: "c64", type: "shelf", platforms: [ "c64" ], kinds: [ "cartridge" ], layout: "flat",
        index: "INDEX.TXT", urls: [] },
      { key: "assembly64", type: "assembly64", platforms: [ "c64" ], hosts: [ "a64.example.org" ],
        path: "/leet/search", repo: "assembly64" }
    ])
  end

  describe "the configuration DSL" do
    let(:config) { WarpEngine::Configuration.new }

    it "defines an outlet, replacing one with the same key, and takes a shelf as an outlet of the type shelf" do
      WarpEngine::Configuration::DSL.apply(config) do
        outlet :assembly64, type: :assembly64, hosts: %w[old.example.org]
        outlet :assembly64, type: :assembly64, hosts: %w[a64.example.org]
        outlet :c64, type: :shelf, platform: "c64", kind: "cartridge", path: "shelves/OLD", extension: ".PRG"
        shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG"
        shelf :dos, key: :apps, kind: "cartridge", layout: "folders", path: "shelves/APPS"
        register_outlet_type :acme, "AcmeOutlet"
      end

      expect(config.outlets).to eq([
        { key: "assembly64", type: "assembly64", hosts: %w[a64.example.org] },
        { key: "c64", type: "shelf", platform: "c64", kind: "cartridge", path: "shelves/C64", extension: ".PRG" },
        { key: "apps", type: "shelf", platform: "dos", kind: "cartridge", layout: "folders", path: "shelves/APPS" }
      ])
      expect(config.outlet_types).to eq("acme" => "AcmeOutlet")
    end
  end
end
