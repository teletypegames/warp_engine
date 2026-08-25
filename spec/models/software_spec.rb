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
