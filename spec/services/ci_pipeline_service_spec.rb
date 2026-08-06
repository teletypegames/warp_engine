require "rails_helper"

RSpec.describe WarpEngine::CiPipelineService do
  let(:client) { instance_double(WarpEngine::WoodpeckerClient) }
  let(:service) { described_class.new(client: client) }

  describe "#trigger" do
    it "delegates to client" do
      repo = build(:ci_repository, repo_owner: "org", repo_name: "game")
      allow(client).to receive(:trigger_pipeline).and_return({ "number" => 6 })

      result = service.trigger(repo, branch: "main")

      expect(result["number"]).to eq(6)
      expect(client).to have_received(:trigger_pipeline).with(repo.woodpecker_repo_id, branch: "main")
    end
  end

  describe "#list_pipelines" do
    it "returns paginated pipelines and refreshes the repo's cached last pipeline" do
      repo = create(:ci_repository, repo_owner: "org", repo_name: "game")
      pipelines = [
        { "number" => 2, "status" => "failure", "created" => 1_754_500_000 },
        { "number" => 1, "status" => "success", "created" => 1_754_400_000 }
      ]
      allow(client).to receive(:list_pipelines).with(repo.woodpecker_repo_id, page: 1).and_return(pipelines)

      expect(service.list_pipelines(repo)).to eq(pipelines)

      repo.reload
      expect(repo.last_pipeline_status).to eq("failure")
      expect(repo.last_pipeline_at).to eq(Time.zone.at(1_754_500_000))
    end

    it "does not touch the cache on later pages" do
      repo = create(:ci_repository, repo_owner: "org", repo_name: "game",
                    last_pipeline_status: "success")
      allow(client).to receive(:list_pipelines).with(repo.woodpecker_repo_id, page: 2)
        .and_return([{ "number" => 1, "status" => "failure", "created" => 1_754_400_000 }])

      service.list_pipelines(repo, page: 2)

      expect(repo.reload.last_pipeline_status).to eq("success")
    end

    it "leaves the cache alone when the repo has no pipelines" do
      repo = create(:ci_repository, repo_owner: "org", repo_name: "game",
                    last_pipeline_status: "success")
      allow(client).to receive(:list_pipelines).and_return([])

      expect(service.list_pipelines(repo)).to eq([])
      expect(repo.reload.last_pipeline_status).to eq("success")
    end
  end
end
