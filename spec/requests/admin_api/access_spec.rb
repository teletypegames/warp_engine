require "rails_helper"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API access", type: :request do
  include AdminApiHelpers

  describe "when the host has not turned it on" do
    before { admin_config.enabled = false }

    it "does not exist, not even for an admin token" do
      get "/api/admin/v1/softwares", headers: auth

      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "Not found")
    end

    it "is off by default" do
      expect(WarpEngine::AdminApi::Configuration.new.enabled?).to be(false)
    end
  end

  it "wants a token, and says how to bring one" do
    get "/api/admin/v1/softwares"

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to start_with("Bearer")
  end

  it "refuses a token without an admin scope" do
    publisher = create(:application_token, owner: admin_owner, scopes: %w[update])

    get "/api/admin/v1/softwares", headers: auth(publisher)

    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses an expired admin token" do
    token = admin_token_with("admin:read", expires_at: 1.hour.from_now)
    token.update_column(:expires_at, 1.minute.ago)

    get "/api/admin/v1/softwares", headers: auth(token)

    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses an admin token whose owner is no longer the admin owner class" do
    token = admin_token
    admin_config.token_owner_class = "Image"

    get "/api/admin/v1/softwares", headers: auth(token)

    expect(response).to have_http_status(:unauthorized)
  end

  it "answers an admin token, names its version, and records the use" do
    api_get "/softwares"

    expect(response).to have_http_status(:ok)
    expect(response.headers["WarpEngine-Admin-Api"]).to eq("1")
    expect(response.headers["WarpEngine-Version"]).to eq(WarpEngine::VERSION)
    expect(admin_token.reload.last_used_at).to be_present
  end

  it "lets a read token read but not write" do
    reader = admin_token_with("admin:read")

    api_get "/softwares", token: reader
    expect(response).to have_http_status(:ok)

    api_post "/softwares", { name: "x", title: "X", platform: "tic80" }, token: reader
    expect(response).to have_http_status(:forbidden)
    expect(json["error"]).to include("admin:write")
  end

  it "does not let a write token read" do
    writer = admin_token_with("admin:write")

    api_get "/softwares", token: writer

    expect(response).to have_http_status(:forbidden)
  end

  it "hides a resource the host left out" do
    admin_config.resources = %i[softwares]

    api_get "/platform_links"
    expect(response).to have_http_status(:not_found)

    api_get "/softwares"
    expect(response).to have_http_status(:ok)
  end

  it "refuses every write when read-only, but still reads" do
    admin_config.read_only = true

    api_post "/softwares", { name: "x", title: "X", platform: "tic80" }
    expect(response).to have_http_status(:method_not_allowed)

    api_get "/softwares"
    expect(response).to have_http_status(:ok)
  end

  it "answers a malformed parameter with 400" do
    api_get "/softwares", params: { highlighted: "perhaps" }

    expect(response).to have_http_status(:bad_request)
    expect(json["error"]).to include("highlighted")
  end

  describe "rate limit" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(cache)
      admin_config.rate_limit = { to: 2, within: 1.minute }
    end

    it "answers 429 with Retry-After past the limit, per token" do
      2.times { api_get "/softwares" }
      expect(response).to have_http_status(:ok)

      api_get "/softwares"
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"].to_i).to be_between(1, 60)

      api_get "/softwares", token: admin_token_with("admin:read")
      expect(response).to have_http_status(:ok)
    end
  end

  describe "a host authenticator" do
    it "is asked instead of the token table" do
      admin_config.authenticator = lambda do |request|
        next nil unless request.headers["X-Api-Key"] == "k3y"

        WarpEngine::AdminApi::Principal.new(owner: admin_owner, scopes: %w[admin:read], label: "key")
      end

      get "/api/admin/v1/softwares", headers: { "X-Api-Key" => "k3y" }
      expect(response).to have_http_status(:ok)

      get "/api/admin/v1/softwares", headers: auth
      expect(response).to have_http_status(:unauthorized)
    end

    it "counts as no answer when it returns something that is not a principal" do
      admin_config.authenticator = ->(_request) { admin_owner }

      get "/api/admin/v1/softwares"

      expect(response).to have_http_status(:unauthorized)
    end

    it "counts as no answer when it raises" do
      admin_config.authenticator = ->(_request) { raise "boom" }

      get "/api/admin/v1/softwares"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /me" do
    it "says who is calling and what they may use" do
      api_get "/me"

      expect(response).to have_http_status(:ok)
      data = json["data"]
      expect(data["scopes"]).to eq(%w[admin:read admin:write])
      expect(data["tokenPrefix"]).to eq(admin_token.token_prefix)
      expect(data["resources"]).to include("softwares", "downloads", "files")
      expect(data["resources"]).not_to include("application_tokens", "pipelines", "meta")
      expect(data["readOnly"]).to be(false)
    end

    it "answers any admin token, whatever its scopes" do
      api_get "/me", token: admin_token_with("admin:tokens")

      expect(response).to have_http_status(:ok)
      expect(json["data"]["resources"]).to eq(%w[application_tokens])
    end
  end

  describe "the write event" do
    it "is published with the principal and the operation" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("warp_engine.admin_api.write") { |*, payload| events << payload }

      api_post "/platform_links", { platform: "tic80", name: "TIC-80", url: "https://tic80.com" }

      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(events.size).to eq(1)
      expect(events.first).to include(operation: "platform_links.create", via: :http)
      expect(events.first[:principal].token).to eq(admin_token)
    end
  end
end
