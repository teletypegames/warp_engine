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

  describe "scopes" do
    it "keeps soft-deleted records out of .kept, not out of .all" do
      active  = create(:platform_link)
      deleted = create(:platform_link, deleted_at: Time.current)

      expect(WarpEngine::PlatformLink.kept).to eq([ active ])
      expect(WarpEngine::PlatformLink.all).to contain_exactly(active, deleted)
    end

    it "does not order: ordering is asked for, not inherited" do
      second = create(:platform_link, position: 2)
      first  = create(:platform_link, position: 1)

      expect(WarpEngine::PlatformLink.ordered).to eq([ first, second ])
      expect(WarpEngine::PlatformLink.all.to_sql).not_to include("ORDER BY")
    end
  end

  describe ".ordered" do
    it "is what .for_platform uses, so the API keeps its link order" do
      second = create(:platform_link, platform: "tic80", position: 2)
      first  = create(:platform_link, platform: "tic80", position: 1)

      expect(WarpEngine::PlatformLink.for_platform("tic80")).to eq([ first, second ])
    end
  end

  describe ".for_platform" do
    it "returns links for given platform only" do
      tic80_link = create(:platform_link, platform: "tic80")
      create(:platform_link, platform: "love")

      result = WarpEngine::PlatformLink.for_platform("tic80")
      expect(result).to eq([ tic80_link ])
    end

    it "returns empty array for platform without links" do
      expect(WarpEngine::PlatformLink.for_platform("godot")).to eq([])
    end
  end
end
