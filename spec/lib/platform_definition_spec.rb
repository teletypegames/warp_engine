require "rails_helper"
require "zip"

RSpec.describe WarpEngine::Platform do
  describe "the builtin definitions" do
    {
      "tic80"      => [ %w[cartridge source html docs win_x64 linux_x64 mac_x64], %w[cartridge] ],
      "ebitengine" => [ %w[html win_x86 win_x64 linux_x64 linux_arm64 mac_x64 mac_arm64], %w[html] ],
      "love"       => [ %w[html win_x64 linux_x64 mac_universal], %w[html] ],
      "c64"        => [ %w[cartridge html win_x64 linux_x64 mac_arm64], %w[cartridge] ],
      "plus4"      => [ %w[cartridge html win_x64 linux_x64 mac_arm64], %w[cartridge] ],
      "godot"      => [ %w[html win_x86 win_x64 linux_x64 mac_universal], %w[html] ],
      "bevy"       => [ %w[html win_x64 linux_x64 linux_arm64], %w[html] ],
      "phaser"     => [ %w[html], %w[html] ],
      "dos"        => [ %w[cartridge win_x86], %w[cartridge] ]
    }.each do |name, (expected, required)|
      it "gives #{name} the kinds it accepts and requires" do
        platform = described_class.find!(name)

        expect(platform.expected_kinds).to eq(expected)
        expect(platform.required_kinds).to eq(required)
      end
    end

    it "keeps the kinds a pipeline does not build out of the built ones" do
      expect(described_class.find!("ebitengine").built_kinds).to eq(%w[html win_x86 win_x64 linux_x64 linux_arm64])
      expect(described_class.find!("dos").optional_kinds).to eq(%w[win_x86])
    end

    it "names every builtin and only them in BUILTIN" do
      expect(described_class::BUILTIN).to eq(%w[tic80 ebitengine love c64 plus4 godot bevy phaser dos])
    end
  end

  describe "an asset kind" do
    it "names the upload and the asset, unpacked or not" do
      docs = WarpEngine::AssetKinds.fetch("docs")
      cartridge = WarpEngine::AssetKinds.fetch("cartridge")

      expect([ docs.upload_name("g-1.0"), docs.asset_name("g-1.0") ]).to eq(%w[g-1.0-docs.zip g-1.0-docs])
      expect(cartridge.upload_name("g-1.0", ext: ".prg")).to eq("g-1.0.prg")
      expect { cartridge.upload_name("g-1.0") }.to raise_error(ArgumentError)
      expect(WarpEngine::ReleaseAsset::KINDS).to eq(WarpEngine::AssetKinds.names)
    end
  end

  describe "a platform a host registers with a block" do
    let(:config) { WarpEngine::Configuration.new }
    let(:dir) { Dir.mktmpdir }

    before do
      File.write(File.join(dir, "amiga.yaml.erb"), <<~YAML)
        steps:
          - name: build
            image: <%= builder %>
            commands: [ "vc -o <%= name %>.adf main.c" ]
      YAML
      template = File.join(dir, "amiga.yaml.erb")
      config.register_platform "amiga" do
        label "Amiga"
        kind :cartridge, ext: ".adf", required: true
        kind :html
        ci template: template
      end
      allow(WarpEngine).to receive(:config).and_return(config)
      allow(config).to receive(:file_container_path).and_return(dir)
    end

    after { FileUtils.remove_entry(dir) }

    it "joins the platforms with its kinds" do
      platform = described_class.find!("amiga")

      expect(described_class.names).to include("amiga")
      expect(platform).not_to be_legacy
      expect([ platform.label, platform.expected_kinds, platform.required_kinds ]).to eq([ "Amiga", %w[cartridge html], %w[cartridge] ])
    end

    it "publishes through the engine's own steps" do
      File.write(File.join(dir, "lemmings-1.0.metadata.json"), { name: "lemmings", title: "Lemmings" }.to_json)
      File.binwrite(File.join(dir, "lemmings-1.0.adf"), "ADF")

      release = described_class.find!("amiga").publish("lemmings", "1.0")

      expect(release.software).to have_attributes(platform: "amiga", title: "Lemmings")
      expect(release.release_assets.map(&:kind)).to eq(%w[cartridge])
    end

    it "builds from its CI-neutral template, with the upload generated from its kinds" do
      yaml = WarpEngine::CI::Gitlab::PipelineConfig.new(platforms: { "amiga" => { builder: "registry.example/vbcc:1" } })
                                                   .render(platform: "amiga", name: "lemmings", update_server: "u")

      expect(YAML.safe_load(yaml)["stages"]).to eq(%w[version build upload publish tag])
      expect(yaml).to include("registry.example/vbcc:1", "vc -o lemmings.adf main.c", "ALWAYS='.adf .metadata.json'", "MAYBE='.html.zip'")
    end

    it "needs a block or a legacy service" do
      expect { config.register_platform "atari" }.to raise_error(ArgumentError)
    end
  end
end
