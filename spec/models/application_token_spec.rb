require "rails_helper"

RSpec.describe WarpEngine::ApplicationToken, type: :model do
  before do
    allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
  end

  describe "token generation" do
    it "generates a plain token on create and stores only its digest and prefix" do
      token = create(:application_token)

      expect(token.plain_token).to match(/\A\h{48}\z/)
      expect(token.token_prefix).to eq(token.plain_token.first(8))
      expect(token.token_digest).to eq(Digest::SHA256.hexdigest(token.plain_token))
    end

    it "does not expose the plain token on a reloaded record" do
      token = create(:application_token)

      expect(described_class.find(token.id).plain_token).to be_nil
    end
  end

  describe "validations" do
    it "requires an owner" do
      token = build(:application_token, owner: nil)

      expect(token).not_to be_valid
      expect(token.errors[:owner]).to be_present
    end

    it "requires a name" do
      expect(build(:application_token, name: nil)).not_to be_valid
    end

    it "requires at least one scope" do
      expect(build(:application_token, scopes: [])).not_to be_valid
    end

    it "fills owner_type from the configuration" do
      token = create(:application_token)

      expect(token.owner_type).to eq("TestOwner")
    end

    it "rejects an owner_type differing from the configuration" do
      token = build(:application_token, owner_type: "WarpEngine::Software")

      expect(token).not_to be_valid
      expect(token.errors[:owner_type]).to be_present
    end

    it "rejects creation when no owner class is configured" do
      allow(WarpEngine.config).to receive(:application_token_owner_class).and_return(nil)
      token = build(:application_token, owner_type: "TestOwner")

      expect(token).not_to be_valid
      expect(token.errors[:base]).to be_present
    end
  end

  describe "#scopes_string" do
    it "round-trips a comma separated list" do
      token = build(:application_token)
      token.scopes_string = "update, deploy,update ,"

      expect(token.scopes).to eq(%w[update deploy])
      expect(token.scopes_string).to eq("update, deploy")
    end
  end

  describe ".authenticate" do
    it "returns the token for a valid plain token and scope" do
      token = create(:application_token)

      expect(described_class.authenticate(token.plain_token, required_scope: "update")).to eq(token)
    end

    it "returns nil for a blank or unknown token" do
      create(:application_token)

      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate("")).to be_nil
      expect(described_class.authenticate("nem-letezo")).to be_nil
    end

    it "returns nil when the required scope is missing" do
      token = create(:application_token, scopes: [ "deploy" ])

      expect(described_class.authenticate(token.plain_token, required_scope: "update")).to be_nil
    end

    it "returns nil for an expired token" do
      token = create(:application_token, :expired)

      expect(described_class.authenticate(token.plain_token, required_scope: "update")).to be_nil
    end

    it "returns nil for a revoked token" do
      token = create(:application_token)
      token.revoke!

      expect(described_class.authenticate(token.plain_token, required_scope: "update")).to be_nil
    end
  end

  describe "#revoke!" do
    it "soft deletes the token" do
      token = create(:application_token)
      token.revoke!

      expect(described_class.kept.find_by(id: token.id)).to be_nil
      expect(described_class.find(token.id).deleted_at).to be_present
    end
  end

  describe "#touch_last_used!" do
    it "stamps last_used_at" do
      token = create(:application_token)

      expect { token.touch_last_used! }.to change { token.reload.last_used_at }.from(nil)
    end
  end
end
