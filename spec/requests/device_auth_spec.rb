require "rails_helper"

# Signing a client in, end to end: the client asks for a code, a person approves it on
# the host's page, the client's next poll carries the token away, and the token then
# works as a bearer credential on the read-only API.
RSpec.describe "Device sign-in", type: :request do
  let(:owner) { create(:test_owner) }

  # The identity seam is off by default. Configuring the subject class is what turns
  # the whole flow on — including whether it exists at all.
  def configure_identity!(verification: "/devices")
    allow(WarpEngine.config).to receive(:access_token_owner_class).and_return("TestOwner")
    allow(WarpEngine.config).to receive(:identity_verification_url).and_return(verification)
  end

  describe "when the host configured no client identity" do
    it "has no device endpoint at all" do
      post "/api/auth/device", params: { client_name: "laptop" }

      expect(response).to have_http_status(:not_found)
    end

    it "says so in the service descriptor rather than by erroring" do
      get "/api/service"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["auth"]).to be_nil
    end
  end

  describe "the full flow" do
    before { configure_identity! }

    it "issues a code pair a person can read off a screen" do
      post "/api/auth/device", params: { client_name: "Zsolt's laptop" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["deviceCode"]).to be_present
      # Grouped and free of I/O/0/1, because it is typed by hand into a browser.
      expect(json["userCode"]).to match(/\A[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}\z/)
      expect(json["verificationUrl"]).to eq("http://www.example.com/devices")
      expect(json["interval"]).to eq(5)
    end

    it "keeps the client waiting until somebody approves" do
      post "/api/auth/device", params: { client_name: "laptop" }
      device_code = JSON.parse(response.body)["deviceCode"]

      post "/api/auth/device/token", params: { device_code: device_code }

      expect(JSON.parse(response.body)).to eq("state" => "pending")
    end

    it "hands over the token on the first poll after approval" do
      post "/api/auth/device", params: { client_name: "laptop" }
      json = JSON.parse(response.body)

      WarpEngine::DeviceGrantService.new.approve(user_code: json["userCode"], subject: owner)
      post "/api/auth/device/token", params: { device_code: json["deviceCode"] }

      body = JSON.parse(response.body)
      expect(body["state"]).to eq("approved")
      expect(body["token"]).to be_present
    end

    # The plain token is never stored, so it cannot be handed out twice. A client that
    # loses it starts again — which is cheaper than a database full of live secrets.
    it "does not repeat the token on a second poll" do
      post "/api/auth/device", params: { client_name: "laptop" }
      json = JSON.parse(response.body)
      WarpEngine::DeviceGrantService.new.approve(user_code: json["userCode"], subject: owner)
      post "/api/auth/device/token", params: { device_code: json["deviceCode"] }

      post "/api/auth/device/token", params: { device_code: json["deviceCode"] }

      body = JSON.parse(response.body)
      expect(body["state"]).to eq("approved")
      expect(body).not_to have_key("token")
    end

    it "reports a denied grant as denied" do
      post "/api/auth/device", params: { client_name: "laptop" }
      json = JSON.parse(response.body)
      WarpEngine::DeviceGrantService.new.deny(user_code: json["userCode"])

      post "/api/auth/device/token", params: { device_code: json["deviceCode"] }

      expect(JSON.parse(response.body)["state"]).to eq("denied")
    end

    it "reports an expired grant as expired" do
      post "/api/auth/device", params: { client_name: "laptop" }
      json = JSON.parse(response.body)
      WarpEngine::DeviceGrant.last.update!(expires_at: 1.minute.ago)

      post "/api/auth/device/token", params: { device_code: json["deviceCode"] }

      expect(JSON.parse(response.body)["state"]).to eq("expired")
    end

    it "404s an unknown device code" do
      post "/api/auth/device/token", params: { device_code: "nope" }

      expect(response).to have_http_status(:not_found)
    end

    it "will not approve the same code twice" do
      post "/api/auth/device", params: { client_name: "laptop" }
      code = JSON.parse(response.body)["userCode"]
      WarpEngine::DeviceGrantService.new.approve(user_code: code, subject: owner)

      expect { WarpEngine::DeviceGrantService.new.approve(user_code: code, subject: owner) }
        .to raise_error(WarpEngine::DeviceGrantService::UnknownCode)
    end

    it "accepts the user code however a person typed it" do
      post "/api/auth/device", params: { client_name: "laptop" }
      code = JSON.parse(response.body)["userCode"]

      grant = WarpEngine::DeviceGrantService.new.approve(
        user_code: code.downcase.delete("-"), subject: owner
      )

      expect(grant).to be_approved
    end
  end

  describe "the issued token" do
    before { configure_identity! }

    let(:token) do
      post "/api/auth/device", params: { client_name: "laptop" }
      json = JSON.parse(response.body)
      WarpEngine::DeviceGrantService.new.approve(user_code: json["userCode"], subject: owner)
      post "/api/auth/device/token", params: { device_code: json["deviceCode"] }
      JSON.parse(response.body)["token"]
    end

    it "belongs to the subject who approved it, and may only read the catalog" do
      token
      record = WarpEngine::ApplicationToken.last

      expect(record.owner).to eq(owner)
      expect(record.scopes).to eq([ "catalog" ])
    end

    # A publishing token must not become a client token by accident, and vice versa:
    # the scope is what separates them, and the catalog endpoint requires its own.
    it "is not accepted as a publishing credential" do
      token

      expect(WarpEngine::ApplicationToken.authenticate(token, required_scope: "update")).to be_nil
    end

    it "identifies the subject on a catalog request" do
      create(:software)
      seen = nil
      policy = Class.new do
        def initialize(sink) = @sink = sink
        def visible_software_scope(subject: nil) = WarpEngine::Software.all
        def access_for(software:, subject: nil)
          @sink.call(subject)
          WarpEngine::Access::OPEN
        end
        def authorize_download(asset: nil, subject: nil, request: nil) = WarpEngine::Access::Grant::OPEN
      end.new(->(s) { seen = s })
      allow(WarpEngine.config).to receive(:access_policy).and_return(policy)

      get "/api/software", headers: { "Authorization" => "Bearer #{token}" }

      expect(seen).to eq(owner)
    end

    it "is ignored when it is not a bearer credential" do
      value = token

      get "/api/software", headers: { "Authorization" => value }

      expect(response).to have_http_status(:ok)
      expect(WarpEngine::ApplicationToken.last.last_used_at).to be_nil
    end

    it "stops working once revoked" do
      value = token

      delete "/api/auth/token", headers: { "Authorization" => "Bearer #{value}" }

      expect(response).to have_http_status(:no_content)
      expect(WarpEngine::ApplicationToken.authenticate(value, required_scope: "catalog")).to be_nil
    end

    it "refuses to revoke without a token" do
      delete "/api/auth/token"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # A browser carries a session, not a bearer token, and the engine has no idea what a
  # session is. A host that wants its signed-in visitors recognised says how.
  describe "the host's own subject resolver" do
    let(:seen) { [] }
    let(:policy) do
      sink = seen
      Class.new do
        def initialize(sink) = @sink = sink
        def visible_software_scope(subject: nil) = WarpEngine::Software.all
        def access_for(software:, subject: nil)
          @sink << subject
          WarpEngine::Access::OPEN
        end
        def authorize_download(asset: nil, subject: nil, request: nil) = WarpEngine::Access::Grant::OPEN
      end.new(sink)
    end

    before do
      create(:software)
      allow(WarpEngine.config).to receive(:access_policy).and_return(policy)
    end

    it "is asked when there is no bearer token" do
      allow(WarpEngine.config).to receive(:subject_resolver).and_return(->(_request) { owner })

      get "/api/software"

      expect(seen).to eq([ owner ])
    end

    it "leaves the request anonymous when the host configured none" do
      get "/api/software"

      expect(seen).to eq([ nil ])
    end

    it "answers anonymously rather than erroring when the resolver breaks" do
      allow(WarpEngine.config).to receive(:subject_resolver).and_return(->(_request) { raise "boom" })

      get "/api/software"

      expect(response).to have_http_status(:ok)
      expect(seen).to eq([ nil ])
    end
  end
end
