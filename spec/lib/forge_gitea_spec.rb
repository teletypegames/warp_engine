require "rails_helper"
require "webmock/rspec"

RSpec.describe WarpEngine::Forge::Gitea do
  subject(:forge) { described_class.new(url: "https://git.example/", token: "t0k", owner: "games") }

  it "creates an empty repository in the organisation" do
    stub = stub_request(:post, "https://git.example/api/v1/orgs/games/repos")
           .with(headers: { "Authorization" => "token t0k" },
                 body: { name: "rabbit", description: "Rabbit", private: false, default_branch: "master", auto_init: false })
           .to_return(status: 201, headers: { "Content-Type" => "application/json" },
                      body: { id: 9, name: "rabbit", owner: { login: "games" }, html_url: "https://git.example/games/rabbit",
                              clone_url: "https://git.example/games/rabbit.git", ssh_url: "ssh://git@git.example/games/rabbit.git" }.to_json)

    repo = forge.create_repo(name: "rabbit", description: "Rabbit")

    expect(stub).to have_been_requested
    expect(repo).to have_attributes(id: 9, owner: "games", name: "rabbit", ssh_url: "ssh://git@git.example/games/rabbit.git")
  end

  it "says what the forge refused" do
    stub_request(:post, "https://git.example/api/v1/orgs/games/repos")
      .to_return(status: 409, body: { message: "The repository with the same name already exists." }.to_json)

    expect { forge.create_repo(name: "rabbit") }
      .to raise_error(WarpEngine::Forge::Error, "Gitea answered 409: The repository with the same name already exists.")
  end

  it "is chosen by the configuration, and absent without one" do
    config = WarpEngine::Configuration.new
    allow(WarpEngine).to receive(:config).and_return(config)
    expect(WarpEngine.forge).to be_a(WarpEngine::Forge::Null)

    config.forge :gitea, url: "https://git.example", token: "t", owner: "games"
    expect(WarpEngine.forge).to be_a(described_class).and(have_attributes(owner: "games", configured?: true))
  end
end
