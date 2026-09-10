require "rails_helper"

RSpec.describe WarpEngine::SoftwareCategory, type: :model do
  it "registers a word it has not seen, flagged for review and placed last" do
    described_class.create!(key: "puzzle", label: "Puzzle", position: 7)

    category = described_class.register("arcade")

    expect(category).to have_attributes(key: "arcade", label: "arcade", needs_review: true, position: 8)
    expect(described_class.register("arcade")).to eq(category)
    expect(described_class.register("")).to be_nil
  end

  it "is registered by a software that takes a category" do
    create(:software, category: "shooter")

    expect(described_class.find_by(key: "shooter")).to have_attributes(needs_review: true)
  end
end
