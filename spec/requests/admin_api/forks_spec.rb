require "rails_helper"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API forks", type: :request do
  include AdminApiHelpers

  let(:software) { create(:software, name: "parent") }
  let!(:link) { WarpEngine::SoftwareFork.create!(software: software, engine_url: "https://other.example", name: "far", status: "pending") }

  it "lists the announced forks by status" do
    WarpEngine::SoftwareFork.create!(software: software, engine_url: "https://other.example", name: "seen", status: "visible")

    api_get "/forks", params: { status: "pending" }

    expect(response).to have_http_status(:ok)
    expect(json["data"].map { |item| item["name"] }).to eq([ "far" ])
    expect(json["data"].first).to include("softwareName" => "parent", "status" => "pending")
  end

  it "moderates one" do
    api_patch "/forks/#{link.id}", { status: "visible" }

    expect(response).to have_http_status(:ok)
    expect(link.reload.status).to eq("visible")
  end

  it "refuses an unknown status" do
    api_patch "/forks/#{link.id}", { status: "maybe" }

    expect(response.status).to be_between(400, 422)
  end

  it "sets, shows and deletes the source of a software" do
    api_get "/softwares/#{software.id}/source"
    expect(response).to have_http_status(:not_found)

    api_put "/softwares/#{software.id}/source", { url: "https://git.example/parent.git", ref: "develop" }
    expect(response).to have_http_status(:ok)
    expect(json["data"]).to include("softwareId" => software.id, "url" => "https://git.example/parent.git", "ref" => "develop",
                                    "public" => nil, "verifiedAt" => nil, "verifyError" => nil)
    expect(json["data"].keys).to include("id", "createdAt", "updatedAt")

    api_get "/softwares/#{software.id}/source"
    expect(json["data"]["url"]).to eq("https://git.example/parent.git")

    api_delete "/softwares/#{software.id}/source"
    expect(response).to have_http_status(:no_content)
    expect(software.reload.source).to be_nil

    api_put "/softwares/#{software.id}/source", { url: "https://git.example/again.git" }
    expect(WarpEngine::SoftwareSource.where(software_id: software.id).count).to eq(1)
  end

  it "refuses a source that is no git address" do
    api_put "/softwares/#{software.id}/source", { url: "not a url" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows the fork fields of a software" do
    api_get "/softwares/#{software.id}"

    expect(json["data"]).to include("forksAllowed" => true, "forkOfEngine" => nil)
  end
end
