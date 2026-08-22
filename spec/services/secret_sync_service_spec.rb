require "rails_helper"

RSpec.describe WarpEngine::SecretSyncService do
  let(:ci) { instance_double(WarpEngine::CI::Woodpecker::Adapter) }
  let(:service) { described_class.new(ci: ci) }

  before do
    allow(WarpEngine.config).to receive(:application_token_source).and_return(:database)
    allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
  end

  describe "#provision" do
    it "hands the token to the provider for every pipeline" do
      repo = create(:pipeline)
      allow(ci).to receive(:secret_set)

      result = service.provision("plaintoken", pipelines: [ repo ])

      expect(result[:synced]).to eq([ repo ])
      expect(ci).to have_received(:secret_set).with(
        repo.remote_repo_id, name: "application_token", value: "plaintoken"
      )
    end

    it "records failed repos without raising" do
      repo = create(:pipeline)
      allow(ci).to receive(:secret_set).and_raise(
        WarpEngine::CI::ConnectionError, "unreachable"
      )

      result = service.provision("tok", pipelines: [ repo ])

      expect(result[:synced]).to be_empty
      expect(result[:failed].size).to eq(1)
    end
  end

  describe "#deprovision" do
    it "deletes secrets from all relevant repos" do
      token = create(:application_token)
      sw = create(:software, name: "game1", owner: token.owner)
      repo = create(:pipeline, :with_software, software: sw)

      allow(ci).to receive(:secret_delete)

      service.deprovision(token)

      expect(ci).to have_received(:secret_delete).with(repo.remote_repo_id, "application_token")
    end
  end

  describe "#rotate" do
    it "creates new token, provisions, revokes old" do
      token = create(:application_token)
      sw = create(:software, name: "game1", owner: token.owner)
      repo = create(:pipeline, :with_software, software: sw)

      allow(ci).to receive(:secret_set)

      result = service.rotate(token)

      expect(result[:rotated]).to be true
      expect(result[:new_token]).to be_a(WarpEngine::ApplicationToken)
      expect(token.reload.deleted_at).to be_present
    end

    it "rolls back if all repos fail" do
      token = create(:application_token)
      sw = create(:software, name: "game1", owner: token.owner)
      create(:pipeline, :with_software, software: sw)

      allow(ci).to receive(:secret_set).and_raise(
        WarpEngine::CI::ConnectionError, "down"
      )

      result = service.rotate(token)

      expect(result[:rotated]).to be false
      expect(token.reload.deleted_at).to be_nil
    end

    it "returns no-op when no repos exist" do
      token = create(:application_token)

      result = service.rotate(token)

      expect(result[:rotated]).to be false
      expect(result[:reason]).to eq("no pipelines")
    end
  end

  describe "#pipelines_for_token" do
    it "returns all active repos for unrestricted tokens" do
      token = create(:application_token, :unrestricted)
      repo1 = create(:pipeline)
      create(:pipeline, :inactive)

      repos = service.pipelines_for_token(token)

      expect(repos).to eq([ repo1 ])
    end

    it "returns only owner's repos for scoped tokens" do
      token = create(:application_token)
      own_sw = create(:software, name: "mine", owner: token.owner)
      other_sw = create(:software, name: "theirs", owner: create(:test_owner))
      own_repo = create(:pipeline, :with_software, software: own_sw)
      create(:pipeline, :with_software, software: other_sw)

      repos = service.pipelines_for_token(token)

      expect(repos).to eq([ own_repo ])
    end
  end
end
