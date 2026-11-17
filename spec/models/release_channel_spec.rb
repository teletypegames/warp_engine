require "rails_helper"

RSpec.describe WarpEngine::Release, "channels" do
  let(:software) { create(:software, name: "rabbit", platform: "c64") }

  def release(version, at)
    create(:release, software: software, version: version, created_at: at)
  end

  it "sets the channel from the version on every save" do
    beta = release("1.3.0-beta.1", 1.day.ago)
    expect(beta.channel).to eq("beta")
    beta.update!(version: "1.3.0")
    expect(beta.channel).to eq("stable")
    expect(release("dev-1.3.0-feature", 1.hour.ago)).to have_attributes(channel: "dev", dev?: true, branch: "feature")
  end

  it "takes the newest stable release as the latest, a newer pre-release only on the beta channel, a dev build never" do
    stable = release("1.2.0", 3.days.ago)
    beta = release("1.3.0-beta.1", 2.days.ago)
    release("dev-1.3.0-feature", 1.day.ago)

    expect(described_class.latest(software.releases.to_a)).to eq(stable)
    expect(described_class.latest(software.releases.to_a, channel: "beta")).to eq(beta)
  end

  it "has no latest release when every one is a development build" do
    release("dev-0.1-develop", 1.day.ago)

    expect(described_class.latest(software.releases.to_a)).to be_nil
  end
end
