require "rails_helper"

RSpec.describe "disabled kinds" do
  let(:c64) { WarpEngine::Platform.find!("c64") }

  describe WarpEngine::Platform do
    it "lists what a software may turn off: the kinds it does not require, web when it plays on the web, stores when a store engine carries it" do
      expect(c64.disableable_kinds).to eq(%w[docs win_x64 linux_x64 mac_arm64 web stores])
      expect(WarpEngine::Platform.find!("phaser").disableable_kinds).to eq(%w[docs web])
      expect(WarpEngine::Platform.find!("golang").disableable_kinds).not_to include("web", "stores", "cli_linux_x64")
    end

    it "leaves the disabled kinds out of every list, and plays nowhere on the web without web" do
      platform = c64.without("web win_x64,linux_x64 mac_arm64")

      expect(platform.expected_kinds).to eq(%w[cartridge docs])
      expect(platform.built_kinds).to eq(%w[cartridge docs])
      expect(platform.optional_kinds).to eq(%w[docs])
      expect(platform.kind_specs.map(&:name)).to eq(%w[cartridge docs])
      expect(platform.web_bindings).to be_empty
      expect(platform.web_binding).to be_nil
      expect(platform.disabled_kinds).to eq(%w[web win_x64 linux_x64 mac_arm64])
    end

    it "ignores a required kind and a name the platform does not know" do
      expect(c64.without(%w[cartridge html nothing])).to equal(c64)
      expect(c64.without([]).expected_kinds).to eq(c64.expected_kinds)
    end

    it "keeps the web when only kinds are disabled" do
      expect(c64.without("win_x64").web_bindings).not_to be_empty
    end

    it "gives a software its platform without what it disables" do
      software = build(:software, platform: "c64", disabled_kinds: %w[web mac_arm64])

      platform = WarpEngine::Platform.for(software)

      expect(platform.expected_kinds).to eq(%w[cartridge docs win_x64 linux_x64])
      expect(platform.web_bindings).to be_empty
    end

    it "reads a list from an Array or from names separated by commas or spaces" do
      expect(WarpEngine::Platform.kind_list(" web, win_x64  web ")).to eq(%w[web win_x64])
      expect(WarpEngine::Platform.kind_list([ :docs, "", "web" ])).to eq(%w[docs web])
      expect(WarpEngine::Platform.kind_list(nil)).to eq([])
    end
  end

  describe WarpEngine::DisabledKindsService do
    let(:tmpdir) { Dir.mktmpdir }
    let(:software) { create(:software, name: "gate", platform: "c64") }
    let(:release) { create(:release, software: software, version: "1.0.0") }

    before do
      allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
      %w[cartridge win_x64 linux_x64].each do |kind|
        path = File.join(tmpdir, "gate", "1.0.0", "gate-1.0.0-#{kind}")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, kind)
        release.release_assets.create!(kind: kind, path: path)
      end
    end

    after { FileUtils.rm_rf(tmpdir) }

    it "lists the assets of the disabled kinds in a dry run and leaves them" do
      software.update!(disabled_kinds: %w[web win_x64 linux_x64])

      report = described_class.new.purge(dry_run: true)

      expect(report.count).to eq(2)
      expect(report.lines.first).to start_with("gate 1.0.0: remove ")
      expect(release.release_assets.kept.count).to eq(3)
    end

    it "soft-deletes the assets of the disabled kinds and removes their files, the rest stays" do
      software.update!(disabled_kinds: %w[stores win_x64])

      described_class.new.purge(softwares: [ software ])

      expect(release.release_assets.kept.map(&:kind)).to contain_exactly("cartridge", "linux_x64")
      expect(File.exist?(File.join(tmpdir, "gate", "1.0.0", "gate-1.0.0-win_x64"))).to be(false)
      expect(File.exist?(File.join(tmpdir, "gate", "1.0.0", "gate-1.0.0-cartridge"))).to be(true)
    end
  end

  describe WarpEngine::Software do
    it "keeps the disabled kinds as a list, empty by default" do
      software = create(:software, platform: "c64", disabled_kinds: "web, win_x64")

      expect(software.reload.disabled_kinds).to eq(%w[web win_x64])
      expect(software.kind_disabled?("win_x64")).to be(true)
      expect(software.web_disabled?).to be(true)
      expect(create(:software, platform: "c64").disabled_kinds).to eq([])
    end

    it "turns everything on again with an empty list" do
      software = create(:software, platform: "c64", disabled_kinds: %w[web])
      software.update!(disabled_kinds: [ "" ])

      expect(software.reload.disabled_kinds).to eq([])
    end

    it "refuses a required kind and a kind of another platform" do
      software = build(:software, platform: "c64", disabled_kinds: %w[cartridge html])

      expect(software).not_to be_valid
      expect(software.errors[:disabled_kinds].first).to include("can only name", "cartridge, html")
    end
  end
end
