require "rails_helper"

RSpec.describe WarpEngine::ScaffoldService do
  let(:owner) { create(:test_owner) }
  let(:repo) do
    WarpEngine::Forge::Repo.new(id: 77, owner: "games", name: "rabbit", html_url: "https://git.example/games/rabbit",
                                clone_url: "https://git.example/games/rabbit.git", ssh_url: "ssh://git@git.example/games/rabbit.git")
  end
  let(:forge) { instance_double(WarpEngine::Forge::Gitea, configured?: true, create_repo: repo) }
  let(:ci) do
    instance_double(WarpEngine::CI::Woodpecker::Adapter, configured?: true, secret_names: [], secret_set: nil,
                                                         activate_forge_repo: WarpEngine::CI::Repo.new(id: 501, name: "rabbit", owner: "games", active: true),
                                                         repo: WarpEngine::CI::Repo.new(id: 501, name: "rabbit", owner: "games", active: true))
  end

  before { allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner") }

  def scaffold(**options)
    described_class.new(forge: forge, ci: ci).scaffold(name: "rabbit", title: "Rabbit", platform: "c64", owner: owner, **options)
  end

  it "gives the software the platform variant it asks for, and refuses one the platform does not have" do
    result = described_class.new(forge: forge, ci: ci).scaffold(name: "rabbit", title: "Rabbit", platform: "golang", app: "gui", owner: owner)

    expect(result.software).to have_attributes(platform: "golang", app: "gui")
    expect { described_class.new(forge: forge, ci: ci).scaffold(name: "hare", title: "Hare", platform: "golang", app: "tui", owner: owner) }
      .to raise_error(described_class::Error, /no app tui/)
  end

  it "creates the repository, the draft software, its pipeline and the CI token in one step" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(described_class::NOTIFICATION) { |*, payload| events << payload }

    result = scaffold(category: "game", description: "A rabbit hops")

    expect(forge).to have_received(:create_repo).with(name: "rabbit", description: "A rabbit hops")
    expect(result.software).to have_attributes(name: "rabbit", title: "Rabbit", platform: "c64", status: "development",
                                               category: "game", desc: "A rabbit hops", owner: owner)
    expect(result.software.external_links.map { |link| [ link.label, link.url, link.kind ] }).to eq([ [ "Repository", repo.clone_url, "source" ] ])
    expect(result.pipeline).to have_attributes(woodpecker_repo_id: 501, software_id: result.software.id, platform: "c64")
    expect(ci).to have_received(:secret_set).with(501, name: "application_token", value: a_string_matching(/\A\h{48}\z/))
    token = WarpEngine::ApplicationToken.last
    expect(token).to have_attributes(name: "rabbit CI", owner: owner, scopes: %w[update upload])
    expect(result.warnings).to eq([])
    expect(events.first).to include(software: result.software, repo: repo)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "records the parent and the license of a fork" do
    result = scaffold(license: "MIT", fork_of: { "engine" => "https://games.example/", "name" => "hare", "version" => "1.0.0" })

    expect(result.software).to have_attributes(license: "MIT", fork_of_engine: "https://games.example", fork_of_name: "hare",
                                               fork_of_version: "1.0.0")
  end

  it "keeps the software when CI cannot be enabled, and says so" do
    allow(ci).to receive(:activate_forge_repo).and_raise(WarpEngine::CI::ApiError.new("forbidden"))

    result = scaffold

    expect(result.software).to be_persisted
    expect(result.pipeline).to be_nil
    expect(result.warnings).to eq([ "CI was not enabled: forbidden" ])
  end

  it "refuses before creating anything" do
    create(:software, name: "taken")

    expect { scaffold(name: "Bad Name") }.to raise_error(described_class::Error, /lower-case/)
    expect { described_class.new(forge: forge, ci: ci).scaffold(name: "taken", title: "T", platform: "c64", owner: owner) }
      .to raise_error(described_class::Error, "taken is taken in the catalog")
    expect { scaffold(platform: "amiga") }.to raise_error(described_class::Error, "amiga is not a platform")
    expect { described_class.new(forge: WarpEngine::Forge::Null.new, ci: ci).scaffold(name: "x", title: "X", platform: "c64", owner: owner) }
      .to raise_error(described_class::Error, "no forge is configured")
    expect(forge).not_to have_received(:create_repo)
  end
end
