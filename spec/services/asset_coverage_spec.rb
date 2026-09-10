require "rails_helper"

RSpec.describe WarpEngine::AssetCoverage do
  def release_with(software:, version:, kinds:, created_at: Time.current)
    release = create(:release, software: software, version: version, created_at: created_at)
    kinds.each { |kind| WarpEngine::ReleaseAsset.create!(release: release, kind: kind, path: "/s/#{version}-#{kind}") }
    release
  end

  describe "#rows" do
    it "says which expected kinds are present and which are missing" do
      software = create(:software, name: "impostor", platform: "tic80")
      release_with(software: software, version: "1.0", kinds: %w[cartridge source html])

      row = described_class.new.rows.first

      expect(row.software).to eq(software)
      expect(row.expected).to eq(WarpEngine::Platform.find("tic80").expected_kinds)
      expect(row.present).to contain_exactly("cartridge", "source", "html")
      expect(row.missing).to contain_exactly("docs", "win_x64", "linux_x64", "mac_x64")
      expect(row).not_to be_complete
    end

    it "calls a release with every expected asset complete" do
      software = create(:software, name: "pong", platform: "c64")
      release_with(software: software, version: "0.1.0", kinds: %w[cartridge html win_x64 linux_x64 mac_arm64])

      row = described_class.new.rows.first

      expect(row).to be_complete
      expect(row.missing).to be_empty
      expect(row).not_to be_actionable
    end

    it "reports an asset the platform does not expect" do
      software = create(:software, name: "phasergame", platform: "phaser")
      release_with(software: software, version: "1.0", kinds: %w[html win_x64])

      row = described_class.new.rows.first

      expect(row.unexpected).to eq([ "win_x64" ])
    end

    it "reports a software with no release at all" do
      create(:software, name: "empty", platform: "godot")

      row = described_class.new.rows.first

      expect(row).not_to be_released
      expect(row).not_to be_actionable
    end

    it "expects nothing from a platform the registry does not know" do
      software = create(:software, name: "amigagame", platform: "tic80")
      software.update_column(:platform, "amiga")
      release_with(software: software, version: "1.0", kinds: [])

      row = described_class.new.rows.first

      expect(row).to be_unknown_platform
      expect(row.expected).to be_empty
    end

    it "checks the newest release by default, and every release on demand" do
      software = create(:software, name: "rabbitroller", platform: "ebitengine")
      release_with(software: software, version: "1.0.0", kinds: %w[html], created_at: 2.days.ago)
      release_with(software: software, version: "1.1.1", kinds: %w[html win_x64], created_at: 1.day.ago)

      expect(described_class.new.rows.map(&:version)).to eq([ "1.1.1" ])
      expect(described_class.new(releases: :all).rows.map(&:version)).to eq([ "1.1.1", "1.0.0" ])
    end

    it "does not call a dev build the latest release" do
      software = create(:software, name: "rabbitroller", platform: "ebitengine")
      release_with(software: software, version: "1.1.1", kinds: %w[html], created_at: 2.days.ago)
      release_with(software: software, version: "dev-abc123-master", kinds: %w[html], created_at: 1.hour.ago)

      expect(described_class.new.rows.map(&:version)).to eq([ "1.1.1" ])
    end

    it "narrows to one software or one platform" do
      create(:software, name: "impostor", platform: "tic80")
      create(:software, name: "rabbitroller", platform: "ebitengine")

      expect(described_class.new(name: "impostor").rows.map { |r| r.software.name }).to eq([ "impostor" ])
      expect(described_class.new(platform: "ebitengine").rows.map { |r| r.software.name }).to eq([ "rabbitroller" ])
    end
  end

  describe "what the CI can build" do
    let(:software) { create(:software, name: "rabbitroller", platform: "ebitengine") }

    before { release_with(software: software, version: "1.1.1", kinds: %w[html]) }

    it "separates the kinds the pipeline builds from the ones it cannot" do
      ci = instance_double(WarpEngine::CI::Woodpecker::Adapter)
      allow(ci).to receive(:built_kinds).with("ebitengine")
        .and_return(%w[html win_x86 win_x64 linux_x64 linux_arm64])
      allow(WarpEngine).to receive(:ci).and_return(ci)

      row = described_class.new.rows.first

      expect(row.buildable_missing).to contain_exactly("win_x86", "win_x64", "linux_x64", "linux_arm64")
      expect(row.manual_missing).to contain_exactly("mac_x64", "mac_arm64")
      expect(row.state_of("linux_arm64")).to eq(:missing)
      expect(row.state_of("mac_x64")).to eq(:manual)
      expect(row.state_of("html")).to eq(:present)
    end

    it "treats every missing kind as buildable when the CI cannot say" do
      ci = instance_double(WarpEngine::CI::Woodpecker::Adapter)
      allow(ci).to receive(:built_kinds).and_return(nil)
      allow(WarpEngine).to receive(:ci).and_return(ci)

      row = described_class.new.rows.first

      expect(row.buildable_missing).to eq(row.missing)
      expect(row.manual_missing).to be_empty
    end
  end

  describe "#totals" do
    it "counts releases, assets and the softwares that are short of one" do
      tic80 = create(:software, name: "impostor", platform: "tic80")
      release_with(software: tic80, version: "1.0", kinds: %w[cartridge source html docs win_x64 linux_x64 mac_x64])
      c64 = create(:software, name: "pong", platform: "c64")
      release_with(software: c64, version: "0.1", kinds: [])

      totals = described_class.new.totals

      expect(totals[:softwares]).to eq(2)
      expect(totals[:releases]).to eq(2)
      expect(totals[:expected]).to eq(12)
      expect(totals[:present]).to eq(7)
      expect(totals[:missing]).to eq(5)
      expect(totals[:incomplete_softwares]).to eq(1)
    end
  end
end
