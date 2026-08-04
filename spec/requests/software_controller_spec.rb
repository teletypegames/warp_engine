require "rails_helper"

RSpec.describe "GET /api/software", type: :request do
  describe "GET /api/software" do
    it "returns all software with releases" do
      create(:software, name: "test-game", title: "Test Game")

      get "/api/software"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["softwares"]).to be_an(Array)
      expect(json["softwares"].length).to eq(1)
    end

    it "returns per-release and total download counts" do
      software = create(:software)
      release  = create(:release, software: software)
      other    = create(:release, software: software)
      create_list(:download, 3, release: release)
      create(:download, release: other)

      get "/api/software"

      json = JSON.parse(response.body)
      sw = json["softwares"].first
      expect(sw["totalDownloads"]).to eq(4)
      counts = sw["releases"].to_h { |r| [ r["id"], r["downloadCount"] ] }
      expect(counts[release.id]).to eq(3)
      expect(counts[other.id]).to eq(1)
    end

    it "excludes soft-deleted software" do
      create(:software, deleted_at: Time.current)

      get "/api/software"

      json = JSON.parse(response.body)
      expect(json["softwares"]).to be_empty
    end
  end
end
