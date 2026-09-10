require "rails_helper"

RSpec.describe WarpEngine::BuildsService do
  describe "#index" do
    subject(:result) { described_class.new.index }

    it "returns all supported platforms with expected kinds" do
      expect(result[:platforms]).to have_key("tic80")
      expect(result[:platforms]["tic80"][:label]).to eq("TIC-80")
      expect(result[:platforms]["tic80"][:kinds]).to include("cartridge", "html")
    end

    it "returns c64 with the cartridge, the browser player and the native players" do
      expect(result[:platforms]["c64"][:kinds]).to eq(%w[cartridge html win_x64 linux_x64 mac_arm64])
    end

    it "returns plus4 with the same kinds as c64" do
      expect(result[:platforms]["plus4"][:label]).to eq("Plus/4")
      expect(result[:platforms]["plus4"][:kinds]).to eq(result[:platforms]["c64"][:kinds])
    end

    it "returns allKinds matching WarpEngine::ReleaseAsset::KINDS" do
      expect(result[:allKinds]).to eq(WarpEngine::ReleaseAsset::KINDS)
    end

    it "includes all supported platforms" do
      WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.each do |platform|
        expect(result[:platforms]).to have_key(platform)
      end
    end
  end

  describe "#show" do
    let!(:software) { create(:software, name: "test-game", platform: "love") }
    let!(:release) { create(:release, software: software, version: "1.0.0") }

    before do
      WarpEngine::ReleaseAsset.create!(release: release, kind: "html", path: "/test/html")
      WarpEngine::ReleaseAsset.create!(release: release, kind: "win_x64", path: "/test/win")
    end

    it "returns expected and actual kinds per release" do
      result = described_class.new.show("test-game")

      expect(result[:platform]).to eq("love")
      expect(result[:expected]).to match_array(%w[html win_x64 linux_x64 mac_universal])
      expect(result[:releases]["1.0.0"][:actual]).to match_array(%w[html win_x64])
      expect(result[:releases]["1.0.0"][:missing]).to match_array(%w[linux_x64 mac_universal])
    end

    it "raises RecordNotFound for unknown software" do
      expect { described_class.new.show("nonexistent") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
