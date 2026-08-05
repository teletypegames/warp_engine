require "rails_helper"

RSpec.describe "GET /update", type: :request do
  before do
    allow(WarpEngine.config).to receive(:update_secret).and_return("s3cret")
  end

  it "rejects requests without a secret" do
    get "/update", params: { platform: "tic80", name: "game", version: "1.0" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects requests with a wrong secret" do
    get "/update", params: { secret: "wrong", platform: "tic80", name: "game", version: "1.0" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects every request when no secret is configured" do
    allow(WarpEngine.config).to receive(:update_secret).and_return(nil)

    get "/update", params: { secret: "", platform: "tic80", name: "game", version: "1.0" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "requires a version" do
    get "/update", headers: { "X-Update-Secret" => "s3cret" }, params: { platform: "tic80", name: "game" }

    expect(response).to have_http_status(:bad_request)
    expect(response.body).to eq("Version not provided")
  end

  it "runs the updater with a valid secret" do
    updater = instance_double(WarpEngine::SoftwareUpdater::Tic80Service)
    allow(WarpEngine::SoftwareUpdater::Tic80Service).to receive(:new).and_return(updater)
    expect(updater).to receive(:update).with("game", "1.0")

    get "/update", headers: { "X-Update-Secret" => "s3cret" },
                   params: { platform: "tic80", name: "game", version: "1.0" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("Updated")
  end

  it "rejects a database token in :env mode" do
    allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
    token = create(:application_token)

    get "/update", headers: { "X-Update-Secret" => token.plain_token },
                   params: { platform: "tic80", name: "game", version: "1.0" }

    expect(response).to have_http_status(:unauthorized)
  end

  context "with update_secret_source :database" do
    before do
      allow(WarpEngine.config).to receive(:update_secret_source).and_return(:database)
      allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
    end

    def stub_updater
      updater = instance_double(WarpEngine::SoftwareUpdater::Tic80Service)
      allow(WarpEngine::SoftwareUpdater::Tic80Service).to receive(:new).and_return(updater)
      allow(updater).to receive(:update)
    end

    it "runs the updater with a valid token and stamps last_used_at" do
      stub_updater
      token = create(:application_token)

      get "/update", headers: { "X-Update-Secret" => token.plain_token },
                     params: { platform: "tic80", name: "game", version: "1.0" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("Updated")
      expect(token.reload.last_used_at).to be_present
    end

    it "accepts the token via the secret param" do
      stub_updater
      token = create(:application_token)

      get "/update", params: { secret: token.plain_token, platform: "tic80", name: "game", version: "1.0" }

      expect(response).to have_http_status(:ok)
    end

    it "rejects the ENV shared secret" do
      get "/update", headers: { "X-Update-Secret" => "s3cret" },
                     params: { platform: "tic80", name: "game", version: "1.0" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a token without the update scope" do
      token = create(:application_token, scopes: [ "deploy" ])

      get "/update", headers: { "X-Update-Secret" => token.plain_token },
                     params: { platform: "tic80", name: "game", version: "1.0" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an expired token" do
      token = create(:application_token, :expired)

      get "/update", headers: { "X-Update-Secret" => token.plain_token },
                     params: { platform: "tic80", name: "game", version: "1.0" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a revoked token" do
      token = create(:application_token)
      token.revoke!

      get "/update", headers: { "X-Update-Secret" => token.plain_token },
                     params: { platform: "tic80", name: "game", version: "1.0" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects every request when no owner class is configured" do
      token = create(:application_token)
      allow(WarpEngine.config).to receive(:application_token_owner_class).and_return(nil)

      get "/update", headers: { "X-Update-Secret" => token.plain_token },
                     params: { platform: "tic80", name: "game", version: "1.0" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
