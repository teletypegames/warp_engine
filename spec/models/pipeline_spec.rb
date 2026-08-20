require "rails_helper"

RSpec.describe WarpEngine::Pipeline do
  describe "validations" do
    subject { build(:pipeline) }

    it { is_expected.to validate_presence_of(:woodpecker_repo_id) }
    it { is_expected.to validate_uniqueness_of(:woodpecker_repo_id) }
    it { is_expected.to validate_presence_of(:repo_owner) }
    it { is_expected.to validate_presence_of(:repo_name) }
    it { is_expected.to validate_presence_of(:platform) }

    it "rejects unsupported platforms" do
      repo = build(:pipeline, platform: "amiga")
      expect(repo).not_to be_valid
      expect(repo.errors[:platform]).to be_present
    end

    WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.each do |p|
      it "accepts #{p}" do
        repo = build(:pipeline, platform: p)
        expect(repo).to be_valid
      end
    end

    it "accepts the unknown placeholder platform" do
      repo = build(:pipeline, platform: WarpEngine::Pipeline::UNKNOWN_PLATFORM)
      expect(repo).to be_valid
    end
  end

  describe "#full_name" do
    it "returns owner/name" do
      repo = build(:pipeline, repo_owner: "games", repo_name: "mygame")
      expect(repo.full_name).to eq("games/mygame")
    end
  end

  describe "default_scope" do
    it "excludes soft-deleted records" do
      repo = create(:pipeline)
      repo.update_column(:deleted_at, Time.current)

      expect(described_class.all).not_to include(repo)
      expect(described_class.unscoped).to include(repo)
    end
  end

  describe ".active" do
    it "returns only active repos" do
      active = create(:pipeline, active: true)
      inactive = create(:pipeline, active: false)

      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(inactive)
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:software).optional }
  end

  describe "assigning a software another pipeline already has" do
    it "moves the link and leaves the other pipeline without one" do
      software = create(:software)
      held_by  = create(:pipeline, software: software, repo_owner: "games", repo_name: "old")
      taking   = create(:pipeline, repo_owner: "games", repo_name: "new")

      taking.update!(software: software)

      expect(taking.reload.software).to eq(software)
      expect(held_by.reload.software).to be_nil
      expect(software.reload.pipeline).to eq(taking)
    end

    it "names the pipelines it took the software from" do
      software = create(:software)
      create(:pipeline, software: software, repo_owner: "games", repo_name: "old")
      taking = create(:pipeline, repo_owner: "games", repo_name: "new")

      taking.update!(software: software)

      expect(taking.software_taken_from).to eq([ "games/old" ])
    end

    it "leaves other pipelines alone when the software is cleared" do
      software = create(:software)
      keeps    = create(:pipeline, software: software, repo_owner: "games", repo_name: "keeps")
      other    = create(:pipeline, repo_owner: "games", repo_name: "other")

      other.update!(software: nil)

      expect(keeps.reload.software).to eq(software)
      expect(other.software_taken_from).to be_nil
    end
  end
end
