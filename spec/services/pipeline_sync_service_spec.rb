require "rails_helper"

RSpec.describe WarpEngine::PipelineSyncService do
  let(:ci) { instance_double(WarpEngine::CI::Woodpecker::Adapter) }
  let(:service) { described_class.new(ci: ci) }

  def ci_repo(id:, name: "mygame", owner: "org", active: true)
    WarpEngine::CI::Repo.new(id: id, name: name, owner: owner, active: active)
  end

  describe "#sync_all" do
    it "creates new Pipeline records from the CI provider" do
      allow(ci).to receive(:repos).and_return([ ci_repo(id: 1) ])

      result = service.sync_all

      expect(result[:created].size).to eq(1)
      repo = result[:created].first
      expect(repo.repo_name).to eq("mygame")
      expect(repo.repo_owner).to eq("org")
      expect(repo.active).to be true
    end

    it "updates existing records" do
      existing = create(:pipeline, woodpecker_repo_id: 1, repo_name: "old", platform: "tic80")
      allow(ci).to receive(:repos).and_return([ ci_repo(id: 1, name: "newname") ])

      result = service.sync_all

      expect(result[:updated].size).to eq(1)
      expect(existing.reload.repo_name).to eq("newname")
    end

    it "deactivates repos the provider no longer has" do
      orphan = create(:pipeline, woodpecker_repo_id: 99, active: true)
      allow(ci).to receive(:repos).and_return([])

      result = service.sync_all

      expect(result[:deactivated]).to include(orphan)
      expect(orphan.reload.active).to be false
    end

    it "auto-detects platform from matching Software" do
      create(:software, name: "mygame", platform: "godot")
      allow(ci).to receive(:repos).and_return([ ci_repo(id: 1) ])

      result = service.sync_all

      expect(result[:created].first.platform).to eq("godot")
      expect(result[:created].first.software).to be_present
    end
  end

  describe "#activate" do
    it "calls the provider and syncs the repo" do
      allow(ci).to receive(:activate_repo).with(42)
      allow(ci).to receive(:repo).with(42).and_return(ci_repo(id: 42, name: "game"))

      repo = service.activate(42)

      expect(repo.woodpecker_repo_id).to eq(42)
      expect(repo.active).to be true
    end
  end

  describe "#deactivate" do
    it "calls the provider and marks the repo inactive" do
      repo = create(:pipeline, woodpecker_repo_id: 42, active: true)
      allow(ci).to receive(:deactivate_repo).with(42)

      service.deactivate(42)

      expect(repo.reload.active).to be false
    end
  end
end
