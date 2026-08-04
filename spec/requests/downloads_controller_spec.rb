require "rails_helper"

RSpec.describe "GET /api/download", type: :request do
  describe "GET /api/download" do
    it "returns bad_request without path" do
      get "/api/download"

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("Path is required")
    end

    it "returns not_found for invalid path" do
      get "/api/download", params: { path: "nonexistent/file.tic" }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("Not found")
    end
  end
end
