require "rails_helper"

RSpec.describe "GET /api/software/vocabulary", type: :request do
  it "lists the seeded statuses in order, with their labels and visibility" do
    get "/api/software/vocabulary"

    json = JSON.parse(response.body)
    expect(json["api"]).to eq(WarpEngine::API_VERSION)
    expect(json["statuses"].map { |s| s["key"] }).to eq(%w[released demo development archived])
    development = json["statuses"].find { |s| s["key"] == "development" }
    expect(development).to include("label" => "In development", "defaultVisible" => false, "badge" => "development")
  end

  it "lists the categories with how many visible softwares carry each" do
    WarpEngine::SoftwareCategory.create!(key: "puzzle", label: "Puzzle", position: 1)
    create(:software, category: "puzzle")
    create(:software, category: "puzzle")
    create(:software, category: "arcade")

    get "/api/software/vocabulary"

    categories = JSON.parse(response.body)["categories"].to_h { |c| [ c["key"], c ] }
    expect(categories["puzzle"]).to include("label" => "Puzzle", "count" => 2)
    expect(categories["arcade"]).to include("label" => "arcade", "count" => 1)
  end
end
