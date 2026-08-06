require "rails_helper"

RSpec.describe "POST /build/publish", type: :request do
  before do
    allow(WarpEngine.config).to receive(:update_secret).and_return("s3cret")
  end

  def stub_updater
    updater = instance_double(WarpEngine::Platforms::Tic80::Service)
    allow(WarpEngine::Platforms::Tic80::Service).to receive(:new).and_return(updater)
    allow(updater).to receive(:update)
    updater
  end

  def publish(headers: { "X-Update-Secret" => "s3cret" }, params: {})
    post "/build/publish", headers: headers,
                           params: { name: "game", platform: "tic80", version: "1.0" }.merge(params)
  end

  it "rejects requests without a secret" do
    publish(headers: {})

    expect(response).to have_http_status(:unauthorized)
  end

  it "does not accept the secret as a query param" do
    post "/build/publish", params: { secret: "s3cret", name: "game", platform: "tic80", version: "1.0" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "runs the updater and returns the published release" do
    updater = stub_updater
    expect(updater).to receive(:update).with("game", "1.0")

    publish

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("published" => true, "name" => "game",
                                                 "platform" => "tic80", "version" => "1.0")
  end

  it "requires name, platform and version" do
    %i[name platform version].each do |key|
      publish(params: { key => "" })

      expect(response).to have_http_status(:bad_request)
    end
  end

  it "rejects an unsupported platform" do
    publish(params: { platform: "amiga" })

    expect(response).to have_http_status(:bad_request)
  end

  context "with application_token_source :database" do
    before do
      allow(WarpEngine.config).to receive(:application_token_source).and_return(:database)
      allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
      stub_updater
    end

    it "accepts a token with the update scope" do
      token = create(:application_token)

      publish(headers: { "X-Update-Secret" => token.plain_token })

      expect(response).to have_http_status(:ok)
    end

    it "rejects the ENV shared secret" do
      publish

      expect(response).to have_http_status(:unauthorized)
    end

    context "with enforce_software_ownership" do
      before { allow(WarpEngine.config).to receive(:enforce_software_ownership).and_return(true) }

      let(:token) { create(:application_token) }

      it "rejects publishing another owner's software" do
        create(:software, name: "game", owner: create(:test_owner))

        publish(headers: { "X-Update-Secret" => token.plain_token })

        expect(response).to have_http_status(:forbidden)
      end

      it "claims an ownerless software for the token owner" do
        software = create(:software, name: "game")

        publish(headers: { "X-Update-Secret" => token.plain_token })

        expect(response).to have_http_status(:ok)
        expect(software.reload.owner).to eq(token.owner)
      end

      it "does not claim ownership with an unrestricted token" do
        software = create(:software, name: "game")
        internal = create(:application_token, :unrestricted)

        publish(headers: { "X-Update-Secret" => internal.plain_token })

        expect(response).to have_http_status(:ok)
        expect(software.reload.owner_id).to be_nil
      end

      it "keeps the existing owner on republish" do
        owner = create(:test_owner)
        software = create(:software, name: "game", owner: owner)
        token = create(:application_token, owner: owner)

        publish(headers: { "X-Update-Secret" => token.plain_token })

        expect(response).to have_http_status(:ok)
        expect(software.reload.owner).to eq(owner)
      end
    end
  end
end
