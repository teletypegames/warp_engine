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
end
