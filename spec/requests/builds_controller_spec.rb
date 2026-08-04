require "rails_helper"

RSpec.describe "GET /api/builds", type: :request do
  describe "GET /api/builds" do
    it "returns the global build matrix" do
      get "/api/builds"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["platforms"]).to be_a(Hash)
      expect(json["platforms"]["tic80"]["label"]).to eq("TIC-80")
      expect(json["platforms"]["tic80"]["kinds"]).to include("cartridge")
      expect(json["allKinds"]).to be_an(Array)
    end
  end
end
