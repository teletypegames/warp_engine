require "rails_helper"

RSpec.describe WarpEngine::Software, type: :model do
  subject { build(:software) }

  it { should validate_presence_of(:name) }
  it { should validate_presence_of(:title) }
  it { should validate_presence_of(:platform) }
  # MySQL utf8mb4_0900_ai_ci collation: az egyediség DB-szinten case-insensitive
  it { should validate_uniqueness_of(:name).case_insensitive }

  # a törlést a DB-szintű ON DELETE CASCADE végzi, a modellen nincs dependent opció
  it { should have_many(:releases) }
  it { should have_many(:external_links) }
  it { should have_many(:software_images).dependent(:destroy) }

  describe "default scope" do
    it "excludes soft-deleted records" do
      active = create(:software)
      create(:software, deleted_at: Time.current)

      expect(WarpEngine::Software.all).to eq([active])
    end
  end
end
