require "rails_helper"

RSpec.describe "Tool sign-in", type: :request do
  let(:admin) { create(:test_owner, name: "admin") }

  def enable_admin_api!
    allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
    WarpEngine.config.admin_api = WarpEngine::AdminApi::Configuration.new.tap { |c| c.enabled = true }
  end

  after { WarpEngine.config.admin_api = nil }

  it "has no tool sign-in without the Admin API" do
    post "/api/auth/device", params: { client_name: "editor", scopes: %w[admin:read] }

    expect(response).to have_http_status(:not_found)
  end

  describe "with the Admin API" do
    before { enable_admin_api! }

    it "starts without a client identity and points to the admin's approval page" do
      post "/api/auth/device", params: { client_name: "WarpEngine Toolbox", scopes: %w[admin:read admin:write] }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["scopes"]).to eq(%w[admin:read admin:write])
      expect(json["verificationUrl"]).to eq("http://www.example.com/admin/tool_sign_in")
      expect(json["verificationUrlComplete"]).to eq("http://www.example.com/admin/tool_sign_in?code=#{json['userCode']}")
    end

    it "refuses a scope that is no Admin API scope" do
      post "/api/auth/device", params: { client_name: "editor", scopes: %w[admin:read update] }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "hands the administrator's token with the asked scopes to the tool once approved" do
      post "/api/auth/device", params: { client_name: "WarpEngine Toolbox", scopes: %w[admin:read] }
      started = JSON.parse(response.body)

      post "/api/auth/device/token", params: { device_code: started["deviceCode"] }
      expect(JSON.parse(response.body)).to eq("state" => "pending")

      WarpEngine::DeviceGrantService.new.approve_tool(user_code: started["userCode"], admin: admin)

      post "/api/auth/device/token", params: { device_code: started["deviceCode"] }
      body = JSON.parse(response.body)
      expect(body["state"]).to eq("approved")
      token = WarpEngine::ApplicationToken.authenticate(body["token"])
      expect(token).to have_attributes(owner: admin, scopes: %w[admin:read], name: "WarpEngine Toolbox")

      get "/api/admin/v1/me", headers: { "Authorization" => "Bearer #{body['token']}" }
      expect(response).to have_http_status(:ok)
    end

    it "keeps tool and catalog approvals apart" do
      grant = WarpEngine::DeviceGrantService.new.request(client_name: "editor", scopes: %w[admin:read])

      expect { WarpEngine::DeviceGrantService.new.deny(user_code: grant.user_code) }
        .to raise_error(WarpEngine::DeviceGrantService::NotConfigured)
      WarpEngine::DeviceGrantService.new.deny_tool(user_code: grant.user_code)
      expect(grant.reload.state).to eq(:denied)
    end
  end
end
