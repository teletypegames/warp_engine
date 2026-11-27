require "rails_helper"

RSpec.describe WarpEngine::ClientConfig do
  it "takes one record per store engine" do
    described_class.create!(client: "batocera")

    expect(described_class.new(client: "batocera")).not_to be_valid
    expect(described_class.new(client: "retroarch")).to be_valid
    expect(described_class.new(client: "pegasus")).not_to be_valid
  end

  it "checks the store id, the statuses and the logos" do
    record = described_class.new(client: "batocera", store_key: "Bad Key", statuses: %w[released nope],
                                 logo_urls: "https://x.example/logo.png\nhttps://x.example/logo.gif")

    expect(record).not_to be_valid
    expect(record.errors.attribute_names).to include(:store_key, :statuses, :logo_urls)
  end

  it "keeps lists without blanks and reads the logos one per line" do
    record = described_class.new(client: "batocera", statuses: [ "", "released" ],
                                 logo_urls: "https://x.example/a.png\n\nhttps://x.example/b.svg")

    expect(record.statuses).to eq(%w[released])
    expect(record.logo_urls).to eq(%w[https://x.example/a.png https://x.example/b.svg])
    expect(described_class.new(statuses: [ "" ]).statuses).to be_nil
  end
end
