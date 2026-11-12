require "rails_helper"

RSpec.describe WarpEngine::Outlets::Assembly64::Query do
  it "reads the query the Ultimate firmware builds" do
    query = described_class.parse('(name:"Thread of Ariadne") & (group:"Teletype") & (category:games) & (rating:>=3)')

    expect(query.conditions).to eq([ [ "name", "Thread of Ariadne" ], %w[group Teletype], %w[category games], [ "rating", ">=3" ] ])
    expect(query["category"]).to eq("games")
    expect(query.keys).to eq(%w[name group category rating])
  end

  it "takes conditions without parentheses, keys in any case, and drops empty values" do
    query = described_class.parse('NAME:"ra" & date:2026 & (type:)')

    expect(query.conditions).to eq([ %w[name ra], %w[date 2026] ])
  end

  it "gives an empty query for text without a condition" do
    [ nil, "", "rubbish", '((("', "&&&" ].each do |text|
      expect(described_class.parse(text)).to be_empty
    end
  end
end
