require "rails_helper"

RSpec.describe WarpEngine::ExternalLink do
  let(:software) { create(:software) }

  it "is a plain link unless it says source" do
    link = described_class.create!(software: software, label: "Site", url: "https://example.org")

    expect(link.kind).to eq("link")
    expect(link).not_to be_source
  end

  it "takes one kept source per software" do
    described_class.create!(software: software, label: "Repository", url: "https://git.example/a.git", kind: "source")
    second = described_class.new(software: software, label: "Mirror", url: "https://git.example/b.git", kind: "source")

    expect(second).not_to be_valid
    expect(second.errors[:kind]).to be_present
  end

  it "lets a source come back once the old one is deleted" do
    described_class.create!(software: software, label: "Repository", url: "https://git.example/a.git", kind: "source").soft_delete!

    expect(described_class.new(software: software, label: "Repository", url: "https://git.example/b.git", kind: "source")).to be_valid
  end

  it "wants a git address for a source" do
    expect(described_class.new(software: software, label: "R", url: "not a url", kind: "source")).not_to be_valid
    expect(described_class.new(software: software, label: "R", url: "git@git.example:games/a.git", kind: "source")).to be_valid
    expect(described_class.new(software: software, label: "R", url: "ssh://git@git.example:2222/games/a.git", kind: "source")).to be_valid
  end

  it "forgets the check when the URL or the ref changes" do
    link = described_class.create!(software: software, label: "R", url: "https://git.example/a.git", kind: "source")
    link.update_columns(public: true, verified_at: Time.current, verify_error: nil)

    link.update!(ref: "develop")

    expect(link.reload.public).to be_nil
    expect(link.verified_at).to be_nil
  end
end
