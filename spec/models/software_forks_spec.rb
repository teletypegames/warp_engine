require "rails_helper"

RSpec.describe WarpEngine::Software, "forks" do
  let(:software) { create(:software) }

  it "is forkable only with a public source and the author's consent" do
    expect(software).not_to be_forkable

    link = WarpEngine::ExternalLink.create!(software: software, label: "R", url: "https://git.example/a.git", kind: "source")
    expect(software.reload).not_to be_forkable

    link.update_columns(public: true)
    expect(software.reload).to be_forkable

    software.update!(forks_allowed: false)
    expect(software).not_to be_forkable
  end

  it "normalizes the parent engine URL and needs a parent name with it" do
    software.fork_of_engine = "HTTPS://Games.Example/"
    expect(software).not_to be_valid

    software.fork_of_name = "parent"
    expect(software).to be_valid
    expect(software.fork_of_engine).to eq("https://games.example")
    expect(software).to be_fork
  end
end
