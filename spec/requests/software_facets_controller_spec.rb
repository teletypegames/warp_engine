require "rails_helper"

RSpec.describe "GET /api/software/facets", type: :request do
  before do
    create(:software, name: "ra", platform: "c64", status: "released", category: "puzzle")
    create(:software, name: "pong", platform: "godot", status: "demo", category: "arcade")
    create(:software, name: "rabbit", platform: "c64", status: "released")
  end

  it "counts every value of every axis when nothing narrows the catalog" do
    get "/api/software/facets"

    json = JSON.parse(response.body)
    expect(json["api"]).to eq(WarpEngine::API_VERSION)
    expect(json["total"]).to eq(3)
    expect(json["statuses"]).to eq("released" => 2, "demo" => 1)
    expect(json["platforms"]).to eq("c64" => 2, "godot" => 1)
    expect(json["categories"]).to eq("puzzle" => 1, "arcade" => 1, "" => 1)
  end

  it "counts each axis against the other filters, not against itself" do
    get "/api/software/facets", params: { platform: "c64" }

    json = JSON.parse(response.body)
    expect(json["total"]).to eq(2)
    expect(json["statuses"]).to eq("released" => 2)
    expect(json["platforms"]).to eq("c64" => 2, "godot" => 1)
    expect(json["categories"]).to eq("puzzle" => 1, "" => 1)
  end

  it "applies the search to every count" do
    get "/api/software/facets", params: { q: "ra" }

    json = JSON.parse(response.body)
    expect(json["total"]).to eq(2)
    expect(json["platforms"]).to eq("c64" => 2)
  end
end
