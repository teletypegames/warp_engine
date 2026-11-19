require "rails_helper"
require_relative "../../support/admin_api_helpers"
require_relative "../../support/local_helpers"

RSpec.describe "Admin API local components", type: :request do
  include AdminApiHelpers
  include LocalHelpers
  include ActiveJob::TestHelper

  it "lists the components and queues their start" do
    api_get "/local_components"
    expect(json["data"].pluck("key", "state")).to eq([ %w[gitea off], %w[woodpecker off] ])

    api_post "/local_components/woodpecker/enable"
    expect(response).to have_http_status(:accepted)
    expect(json["data"]).to include("kind" => "enable", "target" => "woodpecker", "state" => "queued")
    expect(WarpEngine::LocalOperationJob).to have_been_enqueued

    api_get "/local_operations/#{json['data']['id']}"
    expect(json["data"]["state"]).to eq("queued")
  end

  it "queues the set-up of a software" do
    software = create(:software, name: "hopper", platform: "c64")

    api_post "/softwares/#{software.id}/local_ci"

    expect(response).to have_http_status(:accepted)
    expect(json["data"]).to include("kind" => "local_ci", "target" => software.id.to_s, "result" => nil)
  end

  it "shows the generated sign-in only to admin:tokens" do
    ready_component("gitea", secrets: { "admin_password" => "secret-pw" })

    api_get "/local_components/gitea/credentials"
    expect(response).to have_http_status(:forbidden)

    api_get "/local_components/gitea/credentials", token: admin_token_with("admin:read", "admin:tokens")
    expect(json["data"]).to eq("url" => "http://localhost:7471", "user" => "warp-admin", "password" => "secret-pw")
  end

  it "is not there without a runtime" do
    WarpEngine.config.local.runtime = :null

    get "/api/admin/v1/local_components", headers: auth

    expect(response).to have_http_status(:not_found)
  end
end
