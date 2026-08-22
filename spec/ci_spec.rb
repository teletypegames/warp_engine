require "rails_helper"

RSpec.describe WarpEngine::CI do
  after do
    WarpEngine.config.ci_adapter = :woodpecker
    WarpEngine::CI.reset!
  end

  describe ".adapter" do
    it "drives Woodpecker unless the host says otherwise" do
      expect(WarpEngine.ci).to be_a(WarpEngine::CI::Woodpecker::Adapter)
      expect(WarpEngine.ci.name).to eq("Woodpecker")
    end

    it "answers with the null adapter for a host that runs no CI" do
      WarpEngine.config.ci_adapter = :none

      expect(WarpEngine.ci).to be_a(WarpEngine::CI::Null)
      expect(WarpEngine.ci).not_to be_configured
    end

    it "hands back whatever object the host named" do
      own = Class.new { def name = "Forge Runner" }.new
      WarpEngine.config.ci_adapter = own

      expect(WarpEngine.ci).to be(own)
    end
  end

  describe WarpEngine::CI::Null do
    let(:adapter) { described_class.new }

    it "serves no platform and verifies no request" do
      expect(adapter.platforms).to be_empty
      expect(adapter.verify_config_request(nil)).to be(false)
      expect(adapter.config_marker({})).to be_nil
      expect(adapter.pipeline_config(platform: "godot", name: "x", update_server: "y")).to be_nil
    end

    it "raises rather than pretending to manage repositories" do
      expect { adapter.repos }.to raise_error(WarpEngine::CI::NotConfigured)
      expect { adapter.trigger(1) }.to raise_error(WarpEngine::CI::NotConfigured)
    end
  end

  describe WarpEngine::CI::Woodpecker::Adapter do
    let(:client) { instance_double(WarpEngine::CI::Woodpecker::Client) }
    let(:adapter) do
      described_class.new(url: "https://ci.test", api_token: "tok",
                          platforms: { "godot" => { builder: "registry.test/godot:1" } },
                          update_server: "https://games.test")
    end

    before { allow(adapter).to receive(:client).and_return(client) }

    it "is inactive without a server and a token" do
      expect(described_class.new(url: nil, api_token: nil)).not_to be_configured
      expect(adapter).to be_configured
    end

    it "normalizes a repository" do
      allow(client).to receive(:list_repos).and_return([
        { "id" => 7, "name" => "game", "owner" => "org", "active" => true }
      ])

      repo = adapter.repos.first

      expect(repo.id).to eq(7)
      expect(repo.full_name).to eq("org/game")
      expect(repo).to be_active
    end

    it "normalizes a run, timestamp included" do
      allow(client).to receive(:trigger_pipeline).and_return(
        { "number" => 4, "status" => "success", "branch" => "main",
          "message" => "ship it", "created" => 1_754_500_000 }
      )

      run = adapter.trigger(7, branch: "main")

      expect(run.number).to eq(4)
      expect(run).to be_success
      expect(run.created_at).to eq(Time.zone.at(1_754_500_000))
      expect(run.as_json[:createdAt]).to be_present
    end

    it "creates a secret the repository does not have yet" do
      allow(client).to receive(:list_secrets).and_return([])
      allow(client).to receive(:create_secret)

      adapter.secret_set(7, name: "application_token", value: "plain")

      expect(client).to have_received(:create_secret).with(
        7, name: "application_token", value: "plain", events: described_class::SECRET_EVENTS
      )
    end

    it "updates a secret the repository already has" do
      allow(client).to receive(:list_secrets).and_return([ { "name" => "application_token" } ])
      allow(client).to receive(:update_secret)

      adapter.secret_set(7, name: "application_token", value: "plain")

      expect(client).to have_received(:update_secret).with(7, "application_token", value: "plain")
    end

    it "reads the platform marker out of a config request" do
      params = ActionController::Parameters.new(
        repo: { name: "mygame" },
        configuration: [ { name: ".woodpecker.yaml", data: "platform: godot\n" } ]
      )

      expect(adapter.config_marker(params)).to eq({ platform: "godot", name: "mygame" })
    end

    it "ignores a config request that is not a marker" do
      params = ActionController::Parameters.new(
        configuration: [ { name: ".woodpecker.yaml", data: "steps:\n  - name: build\n" } ]
      )

      expect(adapter.config_marker(params)).to be_nil
    end

    it "renders only the platforms it was given" do
      expect(adapter.pipeline_config(platform: "godot", name: "mygame",
                                     update_server: "https://games.test")).to include("registry.test/godot:1")
      expect(adapter.pipeline_config(platform: "amiga", name: "mygame",
                                     update_server: "https://games.test")).to be_nil
    end

    it "shapes the response the way the CI server expects" do
      expect(adapter.config_response(platform: "godot", config: "steps: []"))
        .to eq({ configs: [ { name: "godot", data: "steps: []" } ] })
    end
  end
end
