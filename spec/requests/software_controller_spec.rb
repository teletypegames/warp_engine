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

    it "filters by owner_id and exposes ownerId" do
      owner = create(:test_owner)
      mine  = create(:software, name: "mine", owner: owner)
      create(:software, name: "other", owner: create(:test_owner))
      create(:software, name: "ownerless")

      get "/api/software", params: { owner_id: owner.id }

      json = JSON.parse(response.body)
      expect(json["softwares"].length).to eq(1)
      expect(json["softwares"].first["software"]["name"]).to eq("mine")
      expect(json["softwares"].first["software"]["ownerId"]).to eq(owner.id)
      expect(mine.reload.owner).to eq(owner)
    end

    it "exposes the category, and null where there is none" do
      create(:software, name: "sorted", category: "puzzle")
      create(:software, name: "unsorted")

      get "/api/software"

      json = JSON.parse(response.body)
      categories = json["softwares"].to_h { |sw| [ sw["software"]["name"], sw["software"]["category"] ] }
      expect(categories).to eq("sorted" => "puzzle", "unsorted" => nil)
    end

    it "excludes soft-deleted software" do
      create(:software, deleted_at: Time.current)

      get "/api/software"

      json = JSON.parse(response.body)
      expect(json["softwares"]).to be_empty
    end
  end
end
