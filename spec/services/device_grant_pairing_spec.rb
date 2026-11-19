require "rails_helper"
require_relative "../support/admin_api_helpers"
require_relative "../support/sync_helpers"

RSpec.describe WarpEngine::DeviceGrantService, "pairing" do
  include AdminApiHelpers
  include SyncHelpers

  before { allow(WarpEngine.config.admin_api).to receive(:owner_class_name).and_return("TestOwner") }

  def approved_scopes
    grant = described_class.new.request(client_name: "Toolbox", scopes: %w[admin:read])
    described_class.new.approve_tool(user_code: grant.user_code, admin: admin_owner).application_token.scopes
  end

  it "adds sync:pair to a tool's sign-in while anyone may pair" do
    sync_config(inbound: { enabled: true, pairing: :anyone })

    expect(approved_scopes).to contain_exactly("admin:read", "sync:pair")
  end

  it "adds nothing while only administrators may pair" do
    sync_config(inbound: { enabled: true })

    expect(approved_scopes).to eq(%w[admin:read])
  end
end
