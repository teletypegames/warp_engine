require "rails_helper"

RSpec.describe "GET /api/software", type: :request do
  describe "GET /api/software" do
    it "returns all software with releases, in one envelope, when no page is asked for" do
      create(:software, name: "test-game", title: "Test Game")

      get "/api/software"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["softwares"]).to be_an(Array)
      expect(json["softwares"].length).to eq(1)
      expect(json).to include("api" => WarpEngine::API_VERSION, "page" => 1, "total" => 1, "totalPages" => 1, "nextPage" => nil)
    end

    describe "paging" do
      before do
        %w[delta alpha charlie bravo echo].each { |name| create(:software, name: name, title: name.capitalize) }
      end

      it "hands out pages in title order and says where the next one is" do
        get "/api/software", params: { page: 1, per_page: 2 }

        json = JSON.parse(response.body)
        expect(json.values_at("page", "perPage", "total", "totalPages", "nextPage")).to eq([ 1, 2, 5, 3, 2 ])
        expect(json["softwares"].map { |sw| sw["software"]["title"] }).to eq(%w[Alpha Bravo])

        get "/api/software", params: { page: 3, per_page: 2 }

        json = JSON.parse(response.body)
        expect(json["softwares"].map { |sw| sw["software"]["title"] }).to eq(%w[Echo])
        expect(json["nextPage"]).to be_nil
      end

      it "uses the host's page size when none is asked for, and caps the one that is" do
        allow(WarpEngine.config).to receive_messages(catalog_page_size: 2, catalog_max_page_size: 3)

        get "/api/software", params: { page: 1 }
        expect(JSON.parse(response.body)["perPage"]).to eq(2)

        get "/api/software", params: { page: 1, per_page: 50 }
        expect(JSON.parse(response.body)["perPage"]).to eq(3)
      end

      it "answers a page past the end with an empty page rather than an error" do
        get "/api/software", params: { page: 9, per_page: 2 }

        json = JSON.parse(response.body)
        expect(response).to have_http_status(:ok)
        expect(json["softwares"]).to be_empty
        expect(json["nextPage"]).to be_nil
      end
    end

    describe "filters" do
      before do
        create(:software, name: "ra", title: "Blessing of Ra", platform: "c64", status: "released", category: "puzzle")
        create(:software, name: "pong", title: "Pong", platform: "godot", status: "demo", category: "arcade")
        create(:software, name: "rabbit", title: "Rabbit Scooter", platform: "c64", status: "released")
      end

      def titles(params)
        get "/api/software", params: params
        JSON.parse(response.body)["softwares"].map { |sw| sw["software"]["title"] }
      end

      it "narrows by status, platform and category, and the filters combine" do
        expect(titles(status: "released")).to eq([ "Blessing of Ra", "Rabbit Scooter" ])
        expect(titles(status: "demo,released", platform: "godot")).to eq([ "Pong" ])
        expect(titles(category: "puzzle")).to eq([ "Blessing of Ra" ])
        expect(titles(platform: "c64", category: "arcade")).to be_empty
      end

      it "searches the title and the name" do
        expect(titles(q: "ra")).to eq([ "Blessing of Ra", "Rabbit Scooter" ])
        expect(titles(q: "pong")).to eq([ "Pong" ])
        expect(titles(q: "%")).to be_empty
      end

      it "sorts by what was asked for" do
        expect(titles(sort: "newest")).to eq([ "Rabbit Scooter", "Pong", "Blessing of Ra" ])
      end
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
