require "rails_helper"

# The descriptor is how a client stops being built for one particular store: everything
# it used to have compiled in — is there a sign-in, where does it live, can titles be
# gated — is answered here instead.
RSpec.describe "GET /api/service", type: :request do
  after { WarpEngine::AccessPolicy.reset! }

  it "names the engine and its version" do
    get "/api/service"

    json = JSON.parse(response.body)
    expect(json["engine"]).to eq("warp_engine")
    expect(json["version"]).to eq(WarpEngine::VERSION)
    expect(response.headers["WarpEngine-Version"]).to eq(WarpEngine::VERSION)
  end

  it "reports an open catalog as ungated and offering no sign-in" do
    get "/api/service"

    json = JSON.parse(response.body)
    expect(json["catalog"]).to eq("gated" => false)
    expect(json["auth"]).to be_nil
  end

  it "reports a configured policy as a catalog that can gate" do
    policy = Class.new do
      def visible_software_scope(subject: nil) = WarpEngine::Software.all
      def access_for(software:, subject: nil) = WarpEngine::Access::OPEN
      def authorize_download(asset: nil, subject: nil, request: nil) = WarpEngine::Access::Grant::OPEN
    end.new
    allow(WarpEngine.config).to receive(:access_policy).and_return(policy)

    get "/api/service"

    expect(JSON.parse(response.body)["catalog"]).to eq("gated" => true)
  end

  describe "with a client identity configured" do
    before do
      allow(WarpEngine.config).to receive(:access_token_owner_class).and_return("TestOwner")
      allow(WarpEngine.config).to receive(:identity_verification_url).and_return("/devices")
    end

    it "describes the device flow, so a client needs no addresses of its own" do
      get "/api/service"

      auth = JSON.parse(response.body)["auth"]
      expect(auth["schemes"]).to eq([ "bearer" ])
      expect(auth["device"]["authorizeUrl"]).to eq("http://www.example.com/api/auth/device")
      expect(auth["device"]["tokenUrl"]).to eq("http://www.example.com/api/auth/device/token")
      expect(auth["device"]["revokeUrl"]).to eq("http://www.example.com/api/auth/token")
      expect(auth["device"]["interval"]).to eq(5)
    end

    # A host that configured a bare path should not have to know its own hostname; one
    # that put the approval page on another domain should keep it.
    it "makes a configured path absolute against the request" do
      get "/api/service"

      expect(JSON.parse(response.body)["auth"]["device"]["verificationUrl"])
        .to eq("http://www.example.com/devices")
    end

    it "leaves an absolute verification URL alone" do
      allow(WarpEngine.config).to receive(:identity_verification_url)
        .and_return("https://accounts.example.org/devices")

      get "/api/service"

      expect(JSON.parse(response.body)["auth"]["device"]["verificationUrl"])
        .to eq("https://accounts.example.org/devices")
    end
  end
end
