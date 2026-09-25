require "rails_helper"

RSpec.describe WarpEngine::ApplicationTokenService do
  let(:ci) { instance_double(WarpEngine::CI::Woodpecker::Adapter, configured?: true, name: "Woodpecker") }
  let(:owner) { create(:test_owner) }

  subject(:service) { described_class.new(ci: ci) }

  before { allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner") }

  it "creates a token and pushes it to the owner's pipelines" do
    pipeline = create(:pipeline, software: create(:software, owner: owner))
    allow(ci).to receive(:secret_set)

    result = service.create(name: "CI", scopes: %w[update], owner: owner)

    expect(result).to be_created
    expect(result.sync[:synced]).to eq([ pipeline ])
    expect(ci).to have_received(:secret_set).with(pipeline.remote_repo_id, name: "application_token", value: result.token.plain_token)
  end

  it "does not sync without a CI server or a pipeline" do
    allow(ci).to receive(:configured?).and_return(false)

    result = service.create(name: "CI", scopes: %w[update], owner: owner)

    expect(result.sync).to be_nil
  end

  it "returns the unsaved token when it does not validate" do
    result = service.create(name: "", scopes: %w[update], owner: owner)

    expect(result).not_to be_created
    expect(result.token.errors).to have_key(:name)
  end

  it "revokes a token and removes its secrets" do
    token = create(:application_token, owner: owner)
    allow(ci).to receive(:secret_delete)

    service.revoke(token)

    expect(token.reload.deleted_at).to be_present
  end
end
