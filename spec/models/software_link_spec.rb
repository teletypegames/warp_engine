require "rails_helper"

RSpec.describe WarpEngine::SoftwareLink do
  let(:software) { create(:software) }

  it "is a labelled page of a software" do
    link = described_class.create!(software: software, label: "Site", url: "https://example.org")

    expect(software.reload.links).to eq([ link ])
  end

  it "needs a label and a URL" do
    expect(described_class.new(software: software, url: "https://example.org")).not_to be_valid
    expect(described_class.new(software: software, label: "Site")).not_to be_valid
  end

  it "leaves the soft-deleted links out of the software's" do
    described_class.create!(software: software, label: "Site", url: "https://example.org").soft_delete!

    expect(software.reload.links).to be_empty
  end
end
