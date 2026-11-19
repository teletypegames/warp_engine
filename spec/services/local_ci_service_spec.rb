require "rails_helper"
require "webmock/rspec"
require_relative "../support/local_helpers"

RSpec.describe WarpEngine::LocalCiService do
  include LocalHelpers

  let(:owner) { create(:test_owner) }
  let(:software) { create(:software, name: "hopper", platform: "c64") }

  before do
    stub_request(:get, "http://warp-local-gitea:3000/api/healthz").to_return(status: 200)
    stub_request(:get, "#{LocalHelpers::WOODPECKER}/healthz").to_return(status: 200)
    ready_component("gitea", secrets: { "token" => "t", "admin_password" => "pw", "pusher_token" => "push" })
    ready_component("woodpecker", secrets: { "token" => "wp" })
  end

  it "connects the software through the seams and hands back the push address" do
    repo = WarpEngine::Forge::Repo.new(id: 5, owner: "games", name: "hopper", html_url: "http://localhost:7471/games/hopper",
                                      clone_url: "http://localhost:7471/games/hopper.git", ssh_url: nil)
    connected = WarpEngine::ScaffoldService::Result.new(software: software, repo: repo, pipeline: nil, warnings: [])
    allow_any_instance_of(WarpEngine::ScaffoldService).to receive(:connect).and_return(connected)
    collaborator = stub_request(:put, "#{LocalHelpers::GITEA}/repos/games/hopper/collaborators/warp").to_return(status: 204)
    components = WarpEngine::LocalComponentService.new
    allow(components).to receive(:ensure_role) { |role| WarpEngine::Local.ready(role) }
    operation = described_class.new.queue(software, owner)

    result = described_class.new(components: components).setup(operation)

    expect(collaborator).to have_been_requested
    expect(result).to include(remoteName: "wplocal", pushUrl: "http://warp:push@localhost:7471/games/hopper.git",
                              repoUrl: "http://localhost:7471/games/hopper")
  end

  it "reuses the forge's repository and an active pipeline when run again" do
    forge = instance_double(WarpEngine::Forge::Gitea, configured?: true)
    repo = WarpEngine::Forge::Repo.new(id: 5, owner: "games", name: "hopper", html_url: "h", clone_url: "c", ssh_url: nil)
    allow(forge).to receive(:find_repo).with("hopper").and_return(repo)
    pipeline = WarpEngine::Pipeline.create!(software: software, platform: "c64", repo_owner: "games", repo_name: "hopper", woodpecker_repo_id: 9)

    result = WarpEngine::ScaffoldService.new(forge: forge, ci: WarpEngine::CI::Null.new).connect(software: software, owner: owner)

    expect(result.pipeline).to eq(pipeline)
    expect(software.external_links.pluck(:url)).to eq([ "h" ])
  end
end
