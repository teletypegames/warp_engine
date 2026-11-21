require "rails_helper"
require_relative "../support/forks_helpers"

RSpec.describe "Forks in the catalog API", type: :request do
  include ForksHelpers
  include ActiveJob::TestHelper

  let!(:parent) { create(:software, name: "parent", title: "Parent") }

  before { configure_forks(engine_url: "https://games.example", accept_announcements: true) }

  describe "GET /api/softwares/:name/forks" do
    it "lists the forks" do
      create(:software, name: "child", title: "Child", fork_of_engine: "https://games.example", fork_of_name: "parent")
      WarpEngine::ForkLink.create!(software: parent, child_engine: "https://other.example", child_name: "far", child_title: "Far", status: "visible")

      get "/api/softwares/parent/forks"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to include("api" => WarpEngine::API_VERSION, "software" => "parent")
      expect(json["forks"].map { |fork| [ fork["name"], fork["local"] ] }).to eq([ [ "child", true ], [ "far", false ] ])
    end

    it "is 404 for an unknown software" do
      get "/api/softwares/nothing/forks"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/forks" do
    it "accepts an announcement and queues the check" do
      expect { post "/api/forks", params: { engine: "https://other.example", name: "far" }, as: :json }
        .to have_enqueued_job(WarpEngine::ForkVerifyJob)

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)).to eq("status" => "accepted")
    end

    it "is 422 for a malformed announcement" do
      post "/api/forks", params: { engine: "nope", name: "far" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is 404 where the engine takes no announcements" do
      configure_forks(engine_url: "https://games.example")

      post "/api/forks", params: { engine: "https://other.example", name: "far" }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the software record" do
    it "carries the source, the fork switch, the parent and the fork count" do
      link = WarpEngine::ExternalLink.create!(software: parent, label: "Repository", url: "https://git.example/parent.git", kind: "source")
      link.update_columns(public: true, verified_at: Time.current)
      create(:software, name: "child", fork_of_engine: "https://games.example", fork_of_name: "parent")

      get "/api/software"

      records = JSON.parse(response.body)["softwares"].to_h { |entry| [ entry["software"]["name"], entry["software"] ] }
      expect(records["parent"]).to include("forksAllowed" => true, "forkOf" => nil, "forksCount" => 1)
      expect(records["parent"]["source"]).to include("url" => "https://git.example/parent.git", "public" => true)
      expect(records["parent"]["externalLinks"].first).to include("kind" => "source", "public" => true)
      expect(records["child"]["forkOf"]).to include("engine" => "https://games.example", "name" => "parent", "local" => true)
    end
  end

  describe "GET /api/service" do
    it "tells where announcements go" do
      get "/api/service"

      expect(JSON.parse(response.body)["forks"]).to eq("announcements" => true, "engineUrl" => "https://games.example")
    end
  end
end
