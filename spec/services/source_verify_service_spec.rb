require "rails_helper"

RSpec.describe WarpEngine::SourceVerifyService do
  let(:software) { create(:software) }
  let(:link) { WarpEngine::ExternalLink.create!(software: software, label: "R", url: "https://git.example/a.git", kind: "source") }

  it "marks a source that answers without a sign-in as public" do
    commands = []
    runner = lambda { |command, _timeout|
      commands << command
      [ "abc\trefs/heads/master\n", true ]
    }

    described_class.new(runner: runner).verify(link)

    expect(link.reload).to have_attributes(public: true, verify_error: nil)
    expect(link.verified_at).to be_present
    expect(commands.first).to include("ls-remote", "credential.helper=", "https://git.example/a.git")
  end

  it "marks a source that asks for credentials as not public, with the reason" do
    runner = ->(_command, _timeout) { [ "remote: Unauthorized\nfatal: Authentication failed\n", false ] }

    described_class.new(runner: runner).verify(link)

    expect(link.reload).to have_attributes(public: false, verify_error: "fatal: Authentication failed")
  end

  it "leaves a plain link alone" do
    plain = WarpEngine::ExternalLink.create!(software: software, label: "Site", url: "https://example.org")

    expect(described_class.new(runner: ->(*) { raise "not called" }).verify(plain)).to be_nil
  end

  it "checks the sources that were never checked" do
    link
    checked = WarpEngine::ExternalLink.create!(software: create(:software), label: "R", url: "https://git.example/b.git", kind: "source")
    checked.update_columns(public: true, verified_at: 1.hour.ago)

    count = described_class.new(runner: ->(*) { [ "", true ] }).verify_due

    expect(count).to eq(1)
    expect(link.reload.public).to be(true)
  end
end
