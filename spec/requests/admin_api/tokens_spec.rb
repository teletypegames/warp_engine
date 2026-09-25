require "rails_helper"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API tokens", type: :request do
  include AdminApiHelpers

  let(:keeper) { admin_token_with(%w[admin:read admin:write admin:tokens]) }

  it "needs the admin:tokens scope, even to read" do
    api_get "/application_tokens"

    expect(response).to have_http_status(:forbidden)
    expect(json["error"]).to include("admin:tokens")
  end

  it "lists the live tokens by kind without their secrets" do
    create(:application_token, owner: admin_owner, name: "CI", scopes: %w[update upload])
    create(:application_token, owner: admin_owner, name: "Laptop", scopes: %w[catalog])
    create(:application_token, owner: admin_owner, name: "Revoked", scopes: %w[update], deleted_at: Time.current)

    api_get "/application_tokens", token: keeper, params: { kind: "publishing" }
    expect(json["data"].map { |t| t["name"] }).to eq(%w[CI])
    expect(json["data"].first.keys).not_to include("plainToken", "tokenDigest")

    api_get "/application_tokens", token: keeper, params: { kind: "admin" }
    expect(json["data"].map { |t| t["id"] }).to eq([ keeper.id ])

    api_get "/application_tokens", token: keeper, params: { kind: "clients" }
    expect(json["data"].map { |t| t["name"] }).to eq(%w[Laptop])
  end

  it "issues a token and shows its secret in that one answer only" do
    api_post "/application_tokens", { name: "Deploy", scopes: %w[update] }, token: keeper

    expect(response).to have_http_status(:created)
    plain = json["data"]["plainToken"]
    expect(plain).to be_present
    token = WarpEngine::ApplicationToken.authenticate(plain, required_scope: "update")
    expect(token.owner).to eq(admin_owner)
    expect(json["data"]["sync"]).to be_nil

    api_get "/application_tokens/#{token.id}", token: keeper
    expect(json["data"]).not_to have_key("plainToken")
  end

  describe "no wider than the caller" do
    it "refuses admin scopes the caller does not hold" do
      api_post "/application_tokens", { name: "Wide", scopes: %w[admin:write] }, token: admin_token_with("admin:tokens")

      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to include("admin:write")
    end

    it "refuses unrestricted from a restricted caller" do
      api_post "/application_tokens", { name: "Wide", scopes: %w[admin:read], unrestricted: true }, token: keeper

      expect(response).to have_http_status(:forbidden)
    end

    it "inherits the caller's expiry and refuses a later one" do
      limit = 2.days.from_now.change(usec: 0)
      mortal = admin_token_with(%w[admin:read admin:tokens], expires_at: limit)

      api_post "/application_tokens", { name: "Short", scopes: %w[admin:read] }, token: mortal
      expect(Time.iso8601(json["data"]["expiresAt"])).to eq(limit)

      api_post "/application_tokens", { name: "Long", scopes: %w[admin:read], expiresAt: 1.year.from_now.iso8601 },
               token: mortal
      expect(response).to have_http_status(:forbidden)
    end

    it "will not rotate a token wider than the caller, which would hand over its secret" do
      wide = create(:application_token, owner: admin_owner, scopes: %w[admin:read admin:write admin:tokens])

      api_post "/application_tokens/#{wide.id}/rotate", {}, token: admin_token_with(%w[admin:read admin:tokens])

      expect(response).to have_http_status(:forbidden)
    end
  end

  it "changes a token's name and scopes" do
    token = create(:application_token, owner: admin_owner, scopes: %w[admin:read])

    api_patch "/application_tokens/#{token.id}", { name: "Reader", scopes: %w[admin:read admin:write] }, token: keeper

    expect(json["data"]).to include("name" => "Reader", "scopes" => %w[admin:read admin:write])
  end

  it "revokes a token, but not the one it is holding" do
    token = create(:application_token, owner: admin_owner, scopes: %w[update])

    api_delete "/application_tokens/#{token.id}", token: keeper
    expect(response).to have_http_status(:no_content)
    expect(token.reload.deleted_at).to be_present

    api_delete "/application_tokens/#{keeper.id}", token: keeper
    expect(response).to have_http_status(:conflict)
  end

  it "reports a rotation that had no pipeline to push to" do
    token = create(:application_token, owner: admin_owner, scopes: %w[admin:read])

    api_post "/application_tokens/#{token.id}/rotate", {}, token: keeper

    expect(response).to have_http_status(:conflict)
    expect(json["error"]).to include("no pipelines")
  end

  it "refuses admin scopes on a token whose owner is not the admin owner class" do
    admin_config.token_owner_class = "Image"
    image = create(:image)

    expect(WarpEngine::ApplicationToken.new(name: "x", owner: image, scopes: %w[admin:read])).to be_valid

    token = WarpEngine::ApplicationToken.new(name: "x", owner: admin_owner, scopes: %w[admin:read])
    expect(token).to be_invalid
    expect(token.errors[:scopes].join).to include("Image")
  end

  describe "device sign-ins" do
    it "do not exist without a client identity" do
      api_get "/device_grants", token: keeper

      expect(response).to have_http_status(:not_found)
    end

    it "are listed by state where the host signs clients in" do
      allow(WarpEngine.config).to receive(:access_token_owner_class).and_return("TestOwner")
      WarpEngine::DeviceGrant.create!(client_name: "laptop")
      WarpEngine::DeviceGrant.create!(client_name: "tv", denied_at: Time.current)

      api_get "/device_grants", token: keeper, params: { state: "pending" }

      expect(json["data"].map { |g| g["clientName"] }).to eq(%w[laptop])
      expect(json["data"].first["userCode"]).to match(/\A\w{4}-\w{4}\z/)
    end
  end
end
