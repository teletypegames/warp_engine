require "rails_helper"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API fork links", type: :request do
  include AdminApiHelpers

  let(:software) { create(:software, name: "parent") }
  let!(:link) { WarpEngine::ForkLink.create!(software: software, child_engine: "https://other.example", child_name: "far", status: "pending") }

  it "lists the announced forks by status" do
    WarpEngine::ForkLink.create!(software: software, child_engine: "https://other.example", child_name: "seen", status: "visible")

    api_get "/fork_links", params: { status: "pending" }

    expect(response).to have_http_status(:ok)
    expect(json["data"].map { |item| item["childName"] }).to eq([ "far" ])
    expect(json["data"].first).to include("softwareName" => "parent", "status" => "pending")
  end

  it "moderates one" do
    api_patch "/fork_links/#{link.id}", { status: "visible" }

    expect(response).to have_http_status(:ok)
    expect(link.reload.status).to eq("visible")
  end

  it "refuses an unknown status" do
    api_patch "/fork_links/#{link.id}", { status: "maybe" }

    expect(response.status).to be_between(400, 422)
  end

  it "shows the source fields of an external link and takes a kind" do
    api_post "/softwares/#{software.id}/external_links", { label: "Repository", url: "https://git.example/parent.git", kind: "source" }

    expect(response).to have_http_status(:created)
    expect(json["data"]).to include("kind" => "source", "public" => nil, "ref" => nil)
  end

  it "shows the fork fields of a software" do
    api_get "/softwares/#{software.id}"

    expect(json["data"]).to include("forksAllowed" => true, "forkOfEngine" => nil)
  end
end
