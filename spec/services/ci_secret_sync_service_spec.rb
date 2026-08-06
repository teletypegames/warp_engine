require "rails_helper"

RSpec.describe WarpEngine::CiSecretSyncService do
  let(:client) { instance_double(WarpEngine::WoodpeckerClient) }
  let(:service) { described_class.new(client: client) }

  before do
    allow(WarpEngine.config).to receive(:application_token_source).and_return(:database)
    allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
  end

  describe "#provision" do
    it "creates secrets on repos that don't have one" do
      repo = create(:ci_repository)
      allow(client).to receive(:list_secrets).with(repo.woodpecker_repo_id).and_return([])
      allow(client).to receive(:create_secret)

      result = service.provision("plaintoken", repos: [ repo ])

      expect(result[:synced]).to eq([ repo ])
      expect(client).to have_received(:create_secret).with(
        repo.woodpecker_repo_id, name: "application_token", value: "plaintoken"
      )
    end

    it "updates secrets on repos that already have one" do
      repo = create(:ci_repository)
      allow(client).to receive(:list_secrets).with(repo.woodpecker_repo_id)
        .and_return([ { "name" => "application_token" } ])
      allow(client).to receive(:update_secret)

      result = service.provision("newtoken", repos: [ repo ])

      expect(result[:synced]).to eq([ repo ])
      expect(client).to have_received(:update_secret).with(
        repo.woodpecker_repo_id, "application_token", value: "newtoken"
      )
    end

    it "records failed repos without raising" do
      repo = create(:ci_repository)
      allow(client).to receive(:list_secrets).and_raise(
        WarpEngine::WoodpeckerClient::ConnectionError, "unreachable"
      )

      result = service.provision("tok", repos: [ repo ])

      expect(result[:synced]).to be_empty
      expect(result[:failed].size).to eq(1)
    end
  end

  describe "#deprovision" do
    it "deletes secrets from all relevant repos" do
      token = create(:application_token)
      sw = create(:software, name: "game1", owner: token.owner)
      repo = create(:ci_repository, :with_software, software: sw)

      allow(client).to receive(:delete_secret)

      service.deprovision(token)

      expect(client).to have_received(:delete_secret).with(repo.woodpecker_repo_id, "application_token")
    end
  end

  describe "#rotate" do
    it "creates new token, provisions, revokes old" do
      token = create(:application_token)
      sw = create(:software, name: "game1", owner: token.owner)
      repo = create(:ci_repository, :with_software, software: sw)

      allow(client).to receive(:list_secrets).and_return([])
      allow(client).to receive(:create_secret)

      result = service.rotate(token)

      expect(result[:rotated]).to be true
      expect(result[:new_token]).to be_a(WarpEngine::ApplicationToken)
      expect(token.reload.deleted_at).to be_present
    end

    it "rolls back if all repos fail" do
      token = create(:application_token)
      sw = create(:software, name: "game1", owner: token.owner)
      create(:ci_repository, :with_software, software: sw)

      allow(client).to receive(:list_secrets).and_raise(
        WarpEngine::WoodpeckerClient::ConnectionError, "down"
      )

      result = service.rotate(token)

      expect(result[:rotated]).to be false
      expect(token.reload.deleted_at).to be_nil
    end

    it "returns no-op when no repos exist" do
      token = create(:application_token)

      result = service.rotate(token)

      expect(result[:rotated]).to be false
      expect(result[:reason]).to eq("no repos")
    end
  end

  describe "#repos_for_token" do
    it "returns all active repos for unrestricted tokens" do
      token = create(:application_token, :unrestricted)
      repo1 = create(:ci_repository)
      create(:ci_repository, :inactive)

      repos = service.repos_for_token(token)

      expect(repos).to eq([ repo1 ])
    end

    it "returns only owner's repos for scoped tokens" do
      token = create(:application_token)
      own_sw = create(:software, name: "mine", owner: token.owner)
      other_sw = create(:software, name: "theirs", owner: create(:test_owner))
      own_repo = create(:ci_repository, :with_software, software: own_sw)
      create(:ci_repository, :with_software, software: other_sw)

      repos = service.repos_for_token(token)

      expect(repos).to eq([ own_repo ])
    end
  end
end
