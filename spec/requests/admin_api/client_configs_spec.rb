require "rails_helper"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API store engines", type: :request do
  include AdminApiHelpers

  it "sets a store engine up, changes and drops it" do
    api_post "/client_configs", { client: "batocera", name: "Teletype Games", storeKey: "ttg",
                                 logoUrls: %w[https://x.example/logo.png], statuses: %w[released] }
    expect(response).to have_http_status(:created)
    id = json["data"]["id"]
    expect(json["data"]).to include("client" => "batocera", "storeKey" => "ttg", "logoUrls" => %w[https://x.example/logo.png])

    api_patch "/client_configs/#{id}", { pinnedVersion: "4.3.0" }
    expect(json["data"]["pinnedVersion"]).to eq("4.3.0")

    api_get "/client_configs"
    expect(json["data"].map { |record| record["client"] }).to eq(%w[batocera])

    api_delete "/client_configs/#{id}"
    expect(WarpEngine::ClientConfig.count).to eq(0)
  end

  it "refuses an unknown store engine" do
    api_post "/client_configs", { client: "pegasus" }

    expect(response.status).to be_between(400, 422)
  end
end
