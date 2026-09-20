require "rails_helper"

RSpec.describe "CI API", type: :request do
  let(:ci) { instance_double(WarpEngine::CI::Woodpecker::Adapter, configured?: true, name: "Woodpecker") }

  before do
    allow(WarpEngine).to receive(:ci).and_return(ci)
    allow(WarpEngine.config).to receive(:update_secret).and_return("s3cret")
  end

  describe "GET /api/ci/pipelines" do
    it "returns active repos" do
      create(:pipeline, repo_name: "mygame", platform: "tic80")

      get "/api/ci/pipelines"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
      expect(json.first["repoName"]).to eq("mygame")
      expect(json.first.keys).to include("repoId", "repoOwner", "lastPipelineStatus")
      expect(json.first.keys).not_to include("woodpecker_repo_id", "repo_id")
    end

    it "returns 503 when no CI provider is configured" do
      allow(ci).to receive(:configured?).and_return(false)

      get "/api/ci/pipelines"

      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe "GET /api/ci/pipelines/:id/status" do
    it "returns the repo with its latest run" do
      repo = create(:pipeline, repo_owner: "org", repo_name: "game")
      allow(ci).to receive(:run).with(repo.remote_repo_id, "latest")
        .and_return(WarpEngine::CI::Run.new(number: 1, status: "success"))

      get "/api/ci/pipelines/#{repo.id}/status"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["pipeline"]["repoName"]).to eq("game")
      expect(json["latestRun"]["status"]).to eq("success")
    end

    it "answers without a run when the provider is unreachable" do
      repo = create(:pipeline)
      allow(ci).to receive(:run).and_raise(WarpEngine::CI::ConnectionError, "down")

      get "/api/ci/pipelines/#{repo.id}/status"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["latestRun"]).to be_nil
    end
  end

  describe "POST /api/ci/pipelines/:id/trigger" do
    it "requires authentication" do
      repo = create(:pipeline)

      post "/api/ci/pipelines/#{repo.id}/trigger"

      expect(response).to have_http_status(:unauthorized)
    end

    it "triggers a pipeline with a valid secret" do
      repo = create(:pipeline, repo_owner: "org", repo_name: "game")
      allow(ci).to receive(:trigger).with(repo.remote_repo_id, branch: "main")
        .and_return(WarpEngine::CI::Run.new(number: 7, status: "pending"))

      post "/api/ci/pipelines/#{repo.id}/trigger",
           headers: { "X-Update-Secret" => "s3cret" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["triggered"]).to be true
      expect(json["pipeline"]["number"]).to eq(7)
    end
  end
end
