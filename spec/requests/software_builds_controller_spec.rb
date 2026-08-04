require "rails_helper"

RSpec.describe "GET /api/softwares/:name/builds", type: :request do
  describe "GET /api/softwares/:name/builds" do
    let!(:software) { create(:software, name: "test-game", platform: "love") }
    let!(:release) { create(:release, software: software, version: "2.0.0") }

    before do
      WarpEngine::ReleaseAsset.create!(release: release, kind: "html", path: "/test/html")
    end

    it "returns per-software build info" do
      get "/api/softwares/test-game/builds"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["platform"]).to eq("love")
      expect(json["expected"]).to include("html", "win_x64")
      expect(json["releases"]["2.0.0"]["actual"]).to include("html")
      expect(json["releases"]["2.0.0"]["missing"]).to include("win_x64")
    end

    it "returns 404 for unknown software" do
      get "/api/softwares/nonexistent/builds"

      expect(response).to have_http_status(:not_found)
    end
  end
end
