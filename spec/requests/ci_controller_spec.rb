require "rails_helper"

RSpec.describe "CI API", type: :request do
  before do
    allow(WarpEngine.config).to receive(:woodpecker_url).and_return("https://ci.test")
    allow(WarpEngine.config).to receive(:woodpecker_api_token).and_return("wp-token")
    allow(WarpEngine.config).to receive(:update_secret).and_return("s3cret")
  end

  describe "GET /api/ci/repos" do
    it "returns active repos" do
      repo = create(:ci_repository, repo_name: "mygame", platform: "tic80")

      get "/api/ci/repos"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
      expect(json.first["repo_name"]).to eq("mygame")
    end

    it "returns 503 when woodpecker not configured" do
      allow(WarpEngine.config).to receive(:woodpecker_url).and_return(nil)

      get "/api/ci/repos"

      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe "GET /api/ci/repos/:id/status" do
    it "returns repo with pipeline status" do
      repo = create(:ci_repository, repo_owner: "org", repo_name: "game")
      client = instance_double(WarpEngine::WoodpeckerClient)
      allow(WarpEngine::WoodpeckerClient).to receive(:new).and_return(client)
      allow(client).to receive(:get_pipeline)
        .and_return({ "number" => 1, "status" => "success" })

      get "/api/ci/repos/#{repo.id}/status"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["repo"]["repo_name"]).to eq("game")
    end
  end

  describe "POST /api/ci/repos/:id/trigger" do
    it "requires authentication" do
      repo = create(:ci_repository)

      post "/api/ci/repos/#{repo.id}/trigger"

      expect(response).to have_http_status(:unauthorized)
    end

    it "triggers a pipeline with valid secret" do
      repo = create(:ci_repository, repo_owner: "org", repo_name: "game")
      client = instance_double(WarpEngine::WoodpeckerClient)
      allow(WarpEngine::WoodpeckerClient).to receive(:new).and_return(client)
      allow(client).to receive(:trigger_pipeline)
        .and_return({ "number" => 7, "status" => "pending" })

      post "/api/ci/repos/#{repo.id}/trigger",
           headers: { "X-Update-Secret" => "s3cret" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["triggered"]).to be true
    end
  end
end
