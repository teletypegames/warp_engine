require "rails_helper"
require "webmock/rspec"

RSpec.describe WarpEngine::PreviewCommentJob do
  let(:forge) { WarpEngine::Forge::Gitea.new(url: "https://git.example", token: "t0k", owner: "games") }
  let(:software) { create(:software, name: "rabbit", title: "Rabbit", platform: "c64") }
  let(:release) do
    create(:release, software: software, version: "dev-1.3.0-feature-x", commit_sha: "abcdef1234").tap do |r|
      r.release_assets.create!(kind: "cartridge", path: "/softwares/rabbit/dev-1.3.0-feature-x/rabbit-dev-1.3.0-feature-x.prg")
    end
  end
  let(:pulls_url) { "https://git.example/api/v1/repos/games/rabbit/pulls?state=open&limit=50" }
  let(:comments_url) { "https://git.example/api/v1/repos/games/rabbit/issues/5/comments" }

  before do
    allow(WarpEngine).to receive(:forge).and_return(forge)
    allow(WarpEngine.config).to receive(:site_url).and_return("https://games.example")
    WarpEngine::Pipeline.create!(woodpecker_repo_id: 7, repo_owner: "games", repo_name: "rabbit", platform: "c64", software: software)
    stub_request(:get, pulls_url)
      .to_return(status: 200, body: [ { number: 3, head: { ref: "other" } }, { number: 5, head: { ref: "feature/x" } } ].to_json)
  end

  it "adds a comment to the open pull request of the build's branch" do
    stub_request(:get, comments_url).to_return(status: 200, body: "[]")
    post = stub_request(:post, comments_url).with do |request|
      body = JSON.parse(request.body)["body"]
      body.include?("**Rabbit** `dev-1.3.0-feature-x` (commit `abcdef1`)") &&
        body.include?("https://games.example/file/rabbit/dev-1.3.0-feature-x/rabbit-dev-1.3.0-feature-x.prg") &&
        body.include?(described_class::MARKER)
    end.to_return(status: 201, body: { id: 11 }.to_json)

    described_class.perform_now(release.id)

    expect(post).to have_been_requested
  end

  it "changes its own comment on the next build" do
    stub_request(:get, comments_url)
      .to_return(status: 200, body: [ { id: 9, body: "hello" }, { id: 11, body: "old #{described_class::MARKER}" } ].to_json)
    patch = stub_request(:patch, "https://git.example/api/v1/repos/games/rabbit/issues/comments/11")
            .to_return(status: 200, body: { id: 11 }.to_json)

    described_class.perform_now(release.id)

    expect(patch).to have_been_requested
  end

  it "stays quiet without an open pull request" do
    stub_request(:get, pulls_url).to_return(status: 200, body: "[]")

    expect { described_class.perform_now(release.id) }.not_to raise_error
    expect(a_request(:get, comments_url)).not_to have_been_made
  end

  it "logs a forge refusal instead of failing" do
    stub_request(:get, pulls_url).to_return(status: 403, body: { message: "token does not have at least one of required scope(s)" }.to_json)
    allow(Rails.logger).to receive(:warn)

    described_class.perform_now(release.id)

    expect(Rails.logger).to have_received(:warn).with(/token does not have/)
  end

  it "leaves a stable release alone" do
    stable = create(:release, software: software, version: "1.3.0")

    described_class.perform_now(stable.id)

    expect(a_request(:get, pulls_url)).not_to have_been_made
  end
end
