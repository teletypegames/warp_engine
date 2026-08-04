require "rails_helper"

RSpec.describe WarpEngine::Release, type: :model do
  it { should belong_to(:software) }
  it { should have_many(:downloads) }

  describe "version uniqueness" do
    let(:software) { create(:software) }

    it "prevents duplicate versions for same software" do
      create(:release, software: software, version: "1.0.0")
      dup = build(:release, software: software, version: "1.0.0")
      expect(dup).not_to be_valid
    end

    it "allows same version across different software" do
      other_sw = create(:software)
      create(:release, software: software, version: "1.0.0")
      other = build(:release, software: other_sw, version: "1.0.0")
      expect(other).to be_valid
    end
  end
end
