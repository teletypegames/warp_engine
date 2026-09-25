require "rails_helper"

RSpec.describe WarpEngine::AdminApi::Configuration do
  subject(:config) { described_class.new }

  it "is off, bearer-token based and complete by default" do
    expect(config.enabled?).to be(false)
    expect(config.authenticator).to eq(:application_token)
    expect(config.resource_enabled?(:softwares)).to be(true)
    expect(config.openapi_requires_auth?).to be(true)
    expect(config.mcp?).to be(false)
    expect(config.mcp_excluded?(:application_tokens)).to be(true)
  end

  it "takes the admin owner class from the publishing owner class unless told otherwise" do
    allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("AdminUser")
    expect(config.owner_class_name).to eq("AdminUser")

    config.token_owner_class = "Ops::AdminUser"
    expect(config.owner_class_name).to eq("Ops::AdminUser")
  end

  it "only runs MCP when the Admin API itself is on" do
    config.mcp = true
    expect(config.mcp?).to be(false)

    config.enabled = true
    expect(config.mcp?).to be(true)
  end

  it "narrows the resources to a list" do
    config.resources = %w[softwares]

    expect(config.resource_enabled?(:softwares)).to be(true)
    expect(config.resource_enabled?(:files)).to be(false)
  end
end
