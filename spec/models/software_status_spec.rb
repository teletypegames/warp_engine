require "rails_helper"

RSpec.describe WarpEngine::SoftwareStatus, type: :model do
  it "is seeded with the four statuses the catalog always had, in order" do
    expect(described_class.keys).to eq(%w[released demo development archived])
    expect(described_class.default_visible_keys).to eq(%w[released demo archived])
  end

  it "keeps keys machine-shaped" do
    expect(described_class.new(key: "Early Access", label: "Early access", position: 5)).not_to be_valid
    expect(described_class.new(key: "early-access", label: "Early access", position: 5)).to be_valid
  end

  it "is what a software's status is validated against" do
    expect(build(:software, status: "early-access")).not_to be_valid
    described_class.create!(key: "early-access", label: "Early access", position: 5)
    expect(build(:software, status: "early-access")).to be_valid
  end
end
