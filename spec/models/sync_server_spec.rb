require "rails_helper"

RSpec.describe WarpEngine::SyncServer do
  it "stores the secret encrypted and keeps its prefix" do
    server = described_class.create!(label: "Other", host: "https://other.example/warp/", secret: "abcdefgh12345678")

    expect(server.reload.secret).to eq("abcdefgh12345678")
    expect(server.read_attribute(:secret)).not_to include("abcdefgh12345678")
    expect(server.secret_prefix).to eq("abcdefgh")
    expect(server.base_url).to eq("https://other.example/warp")
  end

  it "keeps the stored secret when an empty one is given" do
    server = described_class.create!(label: "Other", host: "https://other.example", secret: "first-token")
    server.update!(secret: "", label: "Renamed")

    expect(server.reload.secret).to eq("first-token")
  end

  it "needs a URL for the host" do
    server = described_class.new(label: "Other", host: "other.example", secret: "x")

    expect(server).not_to be_valid
    expect(server.errors[:host]).to be_present
  end

  it "accepts plain http in test" do
    expect(described_class.new(label: "Local", host: "http://localhost:3000", secret: "x")).to be_valid
  end
end

RSpec.describe WarpEngine::ApplicationToken, "sync scope" do
  before { allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner") }

  it "makes a sync token unrestricted" do
    token = create(:application_token, scopes: [ "sync" ])

    expect(token).to be_unrestricted
    expect(token).to be_sync
  end

  it "refuses to make a sync token restricted again" do
    token = create(:application_token, scopes: [ "sync" ])
    token.unrestricted = false

    expect(token).not_to be_valid
  end

  it "authenticates with any of several scopes" do
    token = create(:application_token, scopes: [ "sync" ])

    expect(described_class.authenticate(token.plain_token, required_scope: %w[upload sync])).to eq(token)
    expect(described_class.authenticate(token.plain_token, required_scope: "upload")).to be_nil
  end

  it "is not written to any pipeline" do
    create(:pipeline)
    token = create(:application_token, scopes: [ "sync" ])

    expect(WarpEngine::SecretSyncService.new(ci: WarpEngine.ci).pipelines_for_token(token)).to be_empty
  end
end
