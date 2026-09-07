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

  describe "web playable assets" do
    def release_with_html(platform)
      release = build(:release, software: create(:software, platform: platform))
      release.release_assets.build(kind: "html", path: "/test/html")
      release
    end

    it "rejects an html asset on a platform whose updater does not accept one" do
      %w[c64 plus4].each do |platform|
        release = release_with_html(platform)
        expect(release).not_to be_valid
        expect(release.errors[:base].join).to include("download only")
      end
    end

    it "accepts an html asset where the platform expects one" do
      expect(release_with_html("tic80")).to be_valid
    end
  end
end
