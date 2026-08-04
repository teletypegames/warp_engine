require "rails_helper"

RSpec.describe WarpEngine::SoftwareHighlightedService do
  describe "#index" do
    it "returns nil when no highlighted software" do
      create(:software, highlighted: false)

      result = described_class.new.index
      expect(result).to be_nil
    end

    it "returns highlighted software" do
      sw = create(:software, highlighted: true, title: "Featured")

      result = described_class.new.index
      expect(result).not_to be_nil
      expect(result[:software][:title]).to eq("Featured")
    end
  end
end
