require "rails_helper"

RSpec.describe WarpEngine::CiRepository do
  describe "validations" do
    subject { build(:ci_repository) }

    it { is_expected.to validate_presence_of(:woodpecker_repo_id) }
    it { is_expected.to validate_uniqueness_of(:woodpecker_repo_id) }
    it { is_expected.to validate_presence_of(:repo_owner) }
    it { is_expected.to validate_presence_of(:repo_name) }
    it { is_expected.to validate_presence_of(:platform) }

    it "rejects unsupported platforms" do
      repo = build(:ci_repository, platform: "amiga")
      expect(repo).not_to be_valid
      expect(repo.errors[:platform]).to be_present
    end

    WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.each do |p|
      it "accepts #{p}" do
        repo = build(:ci_repository, platform: p)
        expect(repo).to be_valid
      end
    end

    it "accepts the unknown placeholder platform" do
      repo = build(:ci_repository, platform: WarpEngine::CiRepository::UNKNOWN_PLATFORM)
      expect(repo).to be_valid
    end
  end

  describe "#full_name" do
    it "returns owner/name" do
      repo = build(:ci_repository, repo_owner: "games", repo_name: "mygame")
      expect(repo.full_name).to eq("games/mygame")
    end
  end

  describe ".kept scope" do
    it "excludes soft-deleted records" do
      repo = create(:ci_repository)
      repo.update_column(:deleted_at, Time.current)

      expect(described_class.kept).not_to include(repo)
    end

    it "includes soft-deleted records without scope" do
      repo = create(:ci_repository)
      repo.update_column(:deleted_at, Time.current)

      expect(described_class.all).to include(repo)
    end
  end

  describe ".active" do
    it "returns only active kept repos" do
      active = create(:ci_repository, active: true)
      inactive = create(:ci_repository, active: false)

      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(inactive)
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:software).optional }
  end

  describe "assigning a software another CI repository already has" do
    it "moves the link and leaves the other CI repository without one" do
      software = create(:software)
      held_by  = create(:ci_repository, software: software, repo_owner: "games", repo_name: "old")
      taking   = create(:ci_repository, repo_owner: "games", repo_name: "new")

      taking.update!(software: software)

      expect(taking.reload.software).to eq(software)
      expect(held_by.reload.software).to be_nil
      expect(software.reload.ci_repository).to eq(taking)
    end

    it "names the CI repositories it took the software from" do
      software = create(:software)
      create(:ci_repository, software: software, repo_owner: "games", repo_name: "old")
      taking = create(:ci_repository, repo_owner: "games", repo_name: "new")

      taking.update!(software: software)

      expect(taking.software_taken_from).to eq([ "games/old" ])
    end

    it "leaves other CI repositories alone when the software is cleared" do
      software = create(:software)
      keeps    = create(:ci_repository, software: software, repo_owner: "games", repo_name: "keeps")
      other    = create(:ci_repository, repo_owner: "games", repo_name: "other")

      other.update!(software: nil)

      expect(keeps.reload.software).to eq(software)
      expect(other.software_taken_from).to be_nil
    end
  end
end
