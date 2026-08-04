require "rails_helper"

RSpec.describe WarpEngine::PlatformLink, type: :model do
  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:url) }
    it { should validate_presence_of(:platform) }

    it "rejects invalid platform" do
      link = build(:platform_link, platform: "invalid")
      expect(link).not_to be_valid
      expect(link.errors[:platform]).to be_present
    end

    it "accepts valid platforms" do
      WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.each do |p|
        link = build(:platform_link, platform: p)
        expect(link).to be_valid
      end
    end
  end

  describe "default scope" do
    it "excludes soft-deleted records" do
      active = create(:platform_link)
      create(:platform_link, deleted_at: Time.current)

      expect(WarpEngine::PlatformLink.all).to eq([active])
    end

    it "orders by position" do
      second = create(:platform_link, position: 2)
      first  = create(:platform_link, position: 1)

      expect(WarpEngine::PlatformLink.all).to eq([first, second])
    end
  end

  describe ".for_platform" do
    it "returns links for given platform only" do
      tic80_link = create(:platform_link, platform: "tic80")
      create(:platform_link, platform: "love")

      result = WarpEngine::PlatformLink.for_platform("tic80")
      expect(result).to eq([tic80_link])
    end

    it "returns empty array for platform without links" do
      expect(WarpEngine::PlatformLink.for_platform("godot")).to eq([])
    end
  end
end
