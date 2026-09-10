require "rails_helper"

RSpec.describe WarpEngine::Software, type: :model do
  subject { build(:software) }

  it { should validate_presence_of(:name) }
  it { should validate_presence_of(:title) }
  it { should validate_presence_of(:platform) }

  it { should validate_uniqueness_of(:name).case_insensitive }

  it { should have_many(:releases) }
  it { should have_many(:external_links) }
  it { should have_many(:software_images).dependent(:destroy) }

  describe "category" do
    it "stores a trimmed word and turns blank into nothing" do
      expect(create(:software, category: "  puzzle ").category).to eq("puzzle")
      expect(create(:software, category: "   ").category).to be_nil
      expect(create(:software).category).to be_nil
    end

    it "refuses one longer than the column" do
      expect(build(:software, category: "x" * 65)).not_to be_valid
    end
  end

  describe ".kept scope" do
    it "excludes soft-deleted records" do
      active = create(:software)
      create(:software, deleted_at: Time.current)

      expect(WarpEngine::Software.kept).to eq([ active ])
    end

    it "includes soft-deleted records without scope" do
      active = create(:software)
      deleted = create(:software, deleted_at: Time.current)

      expect(WarpEngine::Software.all).to contain_exactly(active, deleted)
    end
  end
end
