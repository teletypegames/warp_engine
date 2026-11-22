require "rails_helper"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API store engines", type: :request do
  include AdminApiHelpers

  it "sets a store engine up, changes and drops it" do
    api_post "/store_clients", { client: "batocera", name: "Teletype Games", storeKey: "ttg",
                                 logoUrls: %w[https://x.example/logo.png], statuses: %w[released] }
    expect(response).to have_http_status(:created)
    id = json["data"]["id"]
    expect(json["data"]).to include("client" => "batocera", "storeKey" => "ttg", "logoUrls" => %w[https://x.example/logo.png])

    api_patch "/store_clients/#{id}", { pinnedVersion: "4.3.0" }
    expect(json["data"]["pinnedVersion"]).to eq("4.3.0")

    api_get "/store_clients"
    expect(json["data"].map { |record| record["client"] }).to eq(%w[batocera])

    api_delete "/store_clients/#{id}"
    expect(WarpEngine::StoreClient.count).to eq(0)
  end

  it "refuses an unknown store engine" do
    api_post "/store_clients", { client: "pegasus" }

    expect(response.status).to be_between(400, 422)
  end
end
