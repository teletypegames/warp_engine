require "rails_helper"

RSpec.describe WarpEngine::CiPipelineService do
  let(:client) { instance_double(WarpEngine::WoodpeckerClient) }
  let(:service) { described_class.new(client: client) }

  describe "#dashboard" do
    it "returns latest pipeline for each active repo" do
      repo = create(:ci_repository, repo_owner: "org", repo_name: "game")
      pipeline = { "number" => 5, "status" => "success", "created_at" => "2026-08-06T12:00:00Z" }
      allow(client).to receive(:latest_pipeline).with("org", "game").and_return(pipeline)

      entries = service.dashboard

      expect(entries.size).to eq(1)
      expect(entries.first[:pipeline]["status"]).to eq("success")
      expect(repo.reload.last_pipeline_status).to eq("success")
    end

    it "handles API errors gracefully per repo" do
      create(:ci_repository, repo_owner: "org", repo_name: "broken")
      allow(client).to receive(:latest_pipeline)
        .and_raise(WarpEngine::WoodpeckerClient::ApiError.new("fail", status: 500))

      entries = service.dashboard

      expect(entries.size).to eq(1)
      expect(entries.first[:pipeline]).to be_nil
    end
  end

  describe "#trigger" do
    it "delegates to client" do
      repo = build(:ci_repository, repo_owner: "org", repo_name: "game")
      allow(client).to receive(:trigger_pipeline).and_return({ "number" => 6 })

      result = service.trigger(repo, branch: "main")

      expect(result["number"]).to eq(6)
      expect(client).to have_received(:trigger_pipeline).with("org", "game", branch: "main")
    end
  end

  describe "#list_pipelines" do
    it "returns paginated pipelines" do
      repo = build(:ci_repository, repo_owner: "org", repo_name: "game")
      pipelines = [{ "number" => 1 }, { "number" => 2 }]
      allow(client).to receive(:list_pipelines).with("org", "game", page: 1).and_return(pipelines)

      expect(service.list_pipelines(repo)).to eq(pipelines)
    end
  end
end
