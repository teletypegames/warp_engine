require "rails_helper"

RSpec.describe WarpEngine::SoftwareSource do
  let(:software) { create(:software) }

  it "is the software's source" do
    source = described_class.create!(software: software, url: "https://git.example/a.git")

    expect(software.reload.source).to eq(source)
  end

  it "takes one kept source per software" do
    described_class.create!(software: software, url: "https://git.example/a.git")
    second = described_class.new(software: software, url: "https://git.example/b.git")

    expect(second).not_to be_valid
    expect(second.errors[:software_id]).to be_present
  end

  it "lets a source come back once the old one is deleted" do
    described_class.create!(software: software, url: "https://git.example/a.git").soft_delete!

    expect(described_class.new(software: software, url: "https://git.example/b.git")).to be_valid
  end

  it "brings the deleted source back rather than making a second one" do
    old = described_class.create!(software: software, url: "https://git.example/a.git")
    old.soft_delete!

    expect(described_class.for(software)).to have_attributes(id: old.id, deleted_at: nil)
  end

  it "wants a git address" do
    expect(described_class.new(software: software, url: "not a url")).not_to be_valid
    expect(described_class.new(software: software, url: "git@git.example:games/a.git")).to be_valid
    expect(described_class.new(software: software, url: "ssh://git@git.example:2222/games/a.git")).to be_valid
  end

  it "forgets the check when the URL or the ref changes" do
    source = described_class.create!(software: software, url: "https://git.example/a.git")
    source.update_columns(public: true, verified_at: Time.current, verify_error: nil)

    source.update!(ref: "develop")

    expect(source.reload.public).to be_nil
    expect(source.verified_at).to be_nil
  end
end
