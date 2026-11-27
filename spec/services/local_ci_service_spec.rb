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
    ready_provider("gitea", secrets: { "token" => "t", "admin_password" => "pw", "pusher_token" => "push" })
    ready_provider("woodpecker", secrets: { "token" => "wp" })
  end

  it "connects the software through the seams and hands back the push address" do
    repo = WarpEngine::Scm::Repo.new(id: 5, owner: "games", name: "hopper", html_url: "http://localhost:7471/games/hopper",
                                      clone_url: "http://localhost:7471/games/hopper.git", ssh_url: nil)
    connected = WarpEngine::ScaffoldService::Result.new(software: software, repo: repo, ci_repository: nil, warnings: [])
    allow_any_instance_of(WarpEngine::ScaffoldService).to receive(:connect).and_return(connected)
    collaborator = stub_request(:put, "#{LocalHelpers::GITEA}/repos/games/hopper/collaborators/warp").to_return(status: 204)
    providers = WarpEngine::LocalProviderService.new
    allow(providers).to receive(:ensure_role) { |role| WarpEngine::Local.ready(role) }
    task = described_class.new.queue(software, owner)

    result = described_class.new(providers: providers).setup(task)

    expect(collaborator).to have_been_requested
    expect(result).to include(remoteName: "wplocal", pushUrl: "http://warp:push@localhost:7471/games/hopper.git",
                              repoUrl: "http://localhost:7471/games/hopper")
  end

  it "reuses the scm's repository and an active CI repository when run again" do
    scm = instance_double(WarpEngine::Scm::Gitea, configured?: true)
    repo = WarpEngine::Scm::Repo.new(id: 5, owner: "games", name: "hopper", html_url: "http://localhost:7471/games/hopper",
                                                                              clone_url: "http://localhost:7471/games/hopper.git", ssh_url: nil)
    allow(scm).to receive(:find_repo).with("hopper").and_return(repo)
    ci_repository = WarpEngine::CiRepository.create!(software: software, platform: "c64", repo_owner: "games", repo_name: "hopper", woodpecker_repo_id: 9)

    result = WarpEngine::ScaffoldService.new(scm: scm, ci: WarpEngine::CI::Null.new).connect(software: software, owner: owner)

    expect(result.ci_repository).to eq(ci_repository)
    expect(WarpEngine::SoftwareSource.kept.where(software: software).pluck(:url)).to eq([ "http://localhost:7471/games/hopper.git" ])
  end
end
