require "rails_helper"

RSpec.describe WarpEngine::Channels do
  it "reads the channel from the version" do
    expect(%w[1.2.0 v1.2.0 1.0 2.2.0].map { |v| described_class.for(v) }).to all(eq("stable"))
    expect(%w[1.0-alpha 1.0-beta1 2.0.0-rc.2 v1.3.0-beta.1].map { |v| described_class.for(v) }).to all(eq("beta"))
    expect(%w[dev-0.1-develop dev-3fb3ed8 dev-1.2.0-feature-x].map { |v| described_class.for(v) }).to all(eq("dev"))
  end

  it "offers stable, or stable and beta, never dev" do
    expect(described_class.offered("stable")).to eq(%w[stable])
    expect(described_class.offered("beta")).to eq(%w[stable beta])
    expect { described_class.offered("dev") }.to raise_error(ArgumentError)
  end

  it "reads the branch of a development build" do
    expect(described_class.branch_of("dev-1.2.0-feature-x")).to eq("feature-x")
    expect(described_class.branch_of("dev-0.1-develop")).to eq("develop")
    expect(described_class.branch_of("dev-3fb3ed8")).to be_nil
    expect(described_class.branch_of("1.2.0")).to be_nil
  end
end
