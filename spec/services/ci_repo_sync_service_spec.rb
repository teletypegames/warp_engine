require "rails_helper"

RSpec.describe WarpEngine::CiRepoSyncService do
  let(:client) { instance_double(WarpEngine::WoodpeckerClient) }
  let(:service) { described_class.new(client: client) }

  describe "#sync_all" do
    it "creates new CiRepository records from Woodpecker" do
      allow(client).to receive(:list_repos).and_return([
        { "id" => 1, "name" => "mygame", "owner" => "org", "active" => true }
      ])

      result = service.sync_all

      expect(result[:created].size).to eq(1)
      repo = result[:created].first
      expect(repo.repo_name).to eq("mygame")
      expect(repo.repo_owner).to eq("org")
      expect(repo.active).to be true
    end

    it "updates existing records" do
      existing = create(:ci_repository, woodpecker_repo_id: 1, repo_name: "old", platform: "tic80")
      allow(client).to receive(:list_repos).and_return([
        { "id" => 1, "name" => "newname", "owner" => "org", "active" => true }
      ])

      result = service.sync_all

      expect(result[:updated].size).to eq(1)
      expect(existing.reload.repo_name).to eq("newname")
    end

    it "deactivates repos missing from Woodpecker" do
      orphan = create(:ci_repository, woodpecker_repo_id: 99, active: true)
      allow(client).to receive(:list_repos).and_return([])

      result = service.sync_all

      expect(result[:deactivated]).to include(orphan)
      expect(orphan.reload.active).to be false
    end

    it "auto-detects platform from matching Software" do
      create(:software, name: "mygame", platform: "godot")
      allow(client).to receive(:list_repos).and_return([
        { "id" => 1, "name" => "mygame", "owner" => "org", "active" => true }
      ])

      result = service.sync_all

      expect(result[:created].first.platform).to eq("godot")
      expect(result[:created].first.software).to be_present
    end
  end

  describe "#activate" do
    it "calls client and syncs the repo" do
      allow(client).to receive(:activate_repo).with(42)
      allow(client).to receive(:get_repo).with(42).and_return(
        { "id" => 42, "name" => "game", "owner" => "org", "active" => true }
      )

      repo = service.activate(42)

      expect(repo.woodpecker_repo_id).to eq(42)
      expect(repo.active).to be true
    end
  end

  describe "#deactivate" do
    it "calls client and marks repo inactive" do
      repo = create(:ci_repository, woodpecker_repo_id: 42, active: true)
      allow(client).to receive(:deactivate_repo).with(42)

      service.deactivate(42)

      expect(repo.reload.active).to be false
    end
  end
end
