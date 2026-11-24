require "rails_helper"

RSpec.describe "platform variants" do
  describe "the golang platform" do
    let(:golang) { WarpEngine::Platform.find!("golang") }

    it "is the cli variant by default, with download-only kinds" do
      expect(golang.app).to eq("cli")
      expect(golang.apps).to eq(%w[cli gui])
      expect(golang.expected_kinds).to eq(%w[cli_linux_x64 cli_win_x64 cli_linux_arm64 cli_mac_x64 cli_mac_arm64 docs])
      expect(golang.required_kinds).to eq(%w[cli_linux_x64])
      expect(golang.expected_kinds.grep(/\Acli_/).map { |kind| WarpEngine::AssetKinds.launchable?(kind) }.uniq).to eq([ false ])
    end

    it "gives the gui variant launchable native kinds, the macOS ones not built" do
      gui = WarpEngine::Platform.find!("golang", app: "gui")

      expect(gui.app).to eq("gui")
      expect(gui.required_kinds).to eq(%w[linux_x64])
      expect(gui.built_kinds).to eq(%w[linux_x64 win_x64 linux_arm64 html docs])
      expect(gui.expected_kinds).to include("mac_x64", "mac_arm64")
      expect(gui.expected_kinds.all? { |kind| WarpEngine::AssetKinds.launchable?(kind) }).to be(true)
    end

    it "finds no variant the platform does not have" do
      expect(WarpEngine::Platform.find("golang", app: "tui")).to be_nil
      expect { WarpEngine::Platform.find!("golang", app: "tui") }.to raise_error(ArgumentError, /app tui/)
    end

    it "finds the platform of a software by its app" do
      software = WarpEngine::Software.new(platform: "golang", app: "gui")

      expect(WarpEngine::Platform.for(software).app).to eq("gui")
    end
  end

  describe "a platform without variants" do
    it "has no app and ignores a blank one" do
      tic80 = WarpEngine::Platform.find!("tic80")

      expect([ tic80.app, tic80.apps ]).to eq([ nil, [] ])
      expect(WarpEngine::Platform.find("tic80", app: "cli")).to be_nil
    end
  end

  describe "the DSL" do
    it "shares the kinds declared outside every variant and takes the marked default" do
      builder = WarpEngine::Platform::Builder.new("demo")
      builder.instance_eval do
        kind :docs
        variant(:a) { kind :html, required: true }
        variant(:b, default: true) { kind :linux_x64 }
      end
      definition = builder.build

      expect(definition.app).to eq("b")
      expect(definition.apps).to eq(%w[b a])
      expect(definition.expected_kinds).to eq(%w[docs linux_x64])
      expect(definition.variant("a").expected_kinds).to eq(%w[docs html])
      expect(definition.variant("a").ci_variables).to include(app: "a")
    end

    it "refuses a variant declared twice" do
      builder = WarpEngine::Platform::Builder.new("demo")

      expect do
        builder.instance_eval do
          variant(:a) { kind :html }
          variant(:a) { kind :html }
        end
      end.to raise_error(ArgumentError, /declared twice/)
    end
  end

  describe "WarpEngine::Software" do
    it "takes an app only from the variants of its platform" do
      expect(build(:software, platform: "golang", app: "gui")).to be_valid
      expect(build(:software, platform: "golang", app: "tui").tap(&:validate).errors[:app]).to include(/must be one of cli, gui/)
      expect(build(:software, platform: "tic80", app: "cli").tap(&:validate).errors[:app]).to include(/is not taken/)
      expect(build(:software, platform: "tic80", app: nil)).to be_valid
    end
  end

  describe "WarpEngine::PublishInputDto" do
    it "accepts an app of the platform only" do
      expect(WarpEngine::PublishInputDto.new(platform: "golang", name: "x", version: "1", app: "gui")).to be_valid
      expect(WarpEngine::PublishInputDto.new(platform: "golang", name: "x", version: "1", app: "tui")).not_to be_valid
      expect(WarpEngine::PublishInputDto.new(platform: "tic80", name: "x", version: "1", app: "cli")).not_to be_valid
    end
  end

  describe "publishing" do
    let(:dir) { Dir.mktmpdir }

    before { allow(WarpEngine.config).to receive(:file_container_path).and_return(dir) }

    after { FileUtils.remove_entry(dir) }

    def upload(name, version, files)
      folder = File.join(dir, name, version)
      FileUtils.mkdir_p(folder)
      File.write(File.join(folder, "#{name}-#{version}.metadata.json"), { name: name, title: name.capitalize }.to_json)
      files.each { |file| File.binwrite(File.join(folder, file), "ZIP") }
    end

    it "records the app of the variant and marks download-only assets in the catalog" do
      upload("c64tui", "1.0.0", %w[c64tui-1.0.0-linux-x64-cli.zip c64tui-1.0.0-mac-arm64-cli.zip])

      release = WarpEngine::Platform.find!("golang").publish("c64tui", "1.0.0")
      assets = WarpEngine::ReleaseSerializer.render_as_hash(release.reload)[:assets]

      expect(release.software).to have_attributes(platform: "golang", app: "cli")
      expect(assets.map { |asset| [ asset[:kind], asset[:launch] ] })
        .to contain_exactly([ "cli_linux_x64", false ], [ "cli_mac_arm64", false ])
    end

    it "refuses a cli release without its required linux build" do
      upload("c64tui", "1.0.0", %w[c64tui-1.0.0-mac-arm64-cli.zip])

      expect { WarpEngine::Platform.find!("golang").publish("c64tui", "1.0.0") }
        .to raise_error(WarpEngine::Platforms::MissingAssetsError, /cli_linux_x64/)
    end

    it "publishes the gui variant with launchable assets" do
      upload("giodemo", "1.0.0", %w[giodemo-1.0.0-linux-x64.zip giodemo-1.0.0-win-x64.zip])

      release = WarpEngine::Platform.find!("golang", app: "gui").publish("giodemo", "1.0.0")
      assets = WarpEngine::ReleaseSerializer.render_as_hash(release.reload)[:assets]

      expect(release.software.app).to eq("gui")
      expect(assets.pluck(:kind)).to contain_exactly("linux_x64", "win_x64")
      expect(assets.pluck(:launch).compact).to be_empty
    end
  end

  describe "the golang pipeline" do
    let(:config) { WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "golang" => { builder: "golang-builder:1" } }) }

    def render(options = {})
      config.render(platform: "golang", name: "c64tui", update_server: "https://example.test", options: options)
    end

    it "builds every cli target without cgo and publishes without an app parameter of its own" do
      yaml = render

      expect(yaml).to include("warp_target '-mac-arm64-cli.zip' optional go_build 'darwin' 'arm64' '0'")
      expect(yaml).to include("warp_target '-linux-x64-cli.zip' required go_build 'linux' 'amd64' '0'")
      expect(yaml).not_to include("GOOS=js")
      expect(yaml).to include("APP='cli'")
    end

    it "builds the gui variant natively, with cgo on Linux and an optional web build" do
      yaml = render("app" => "gui")

      expect(yaml).to include("warp_target '-linux-x64.zip' required go_build 'linux' 'amd64' '1' ''")
      expect(yaml).to include("-H=windowsgui")
      expect(yaml).to include("GOOS=js GOARCH=wasm")
      expect(yaml).to include("APP='gui'")
    end

    it "uses no braced positional parameter, which Woodpecker would substitute away" do
      expect([ render, render("app" => "gui") ].join).not_to match(/\$\{[0-9]/)
    end

    it "renders nothing for an app the platform does not have" do
      expect(render("app" => "tui")).to be_nil
    end

    it "names the built kinds of each variant" do
      expect(config.built_kinds("golang")).to eq(%w[cli_linux_x64 cli_win_x64 cli_linux_arm64 cli_mac_x64 cli_mac_arm64 docs])
      expect(config.built_kinds("golang", app: "gui")).to eq(%w[linux_x64 win_x64 linux_arm64 html docs])
    end
  end

  describe "the platform description" do
    it "lists the variants with their marker and kinds" do
      apps = WarpEngine::PlatformDescriptionService.new.find("golang")["apps"]

      expect(apps.map { |app| [ app["name"], app["default"], app["marker"] ] })
        .to eq([ [ "cli", true, "app: cli" ], [ "gui", false, "app: gui" ] ])
      expect(apps.last["kinds"].map { |kind| kind["name"] }).to include("linux_x64", "html")
    end
  end
end
