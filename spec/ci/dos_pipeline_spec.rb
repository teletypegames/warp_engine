require "rails_helper"

shared_examples "dos pipeline" do |config_class, jobs_of|
  let(:store) do
    { image: "registry.example/deploy-ssh:1", target: "deploy@store.example", known_host: "store.example ssh-ed25519 AAAA" }
  end

  def render(config_class, spec, options: {})
    config_class.new(platforms: { "dos" => { builder: "registry.example/dos-ci:1", tools: "registry.example/ci-tools:1" }.merge(spec) })
                .render(platform: "dos", name: "dosinst", update_server: "https://games.example", options: options)
  end

  it "leaves the forge release out unless the host asks for it" do
    jobs = jobs_of.call(YAML.safe_load(render(config_class, {})))

    expect(jobs.keys).to eq(%w[test package artifact publish])
  end

  it "adds the forge release, made by the builder image's dos-release, when forge_release is on" do
    yaml = render(config_class, { forge_release: true })
    jobs = jobs_of.call(YAML.safe_load(yaml))

    expect(jobs.keys).to eq(%w[test package release artifact publish])
    expect(yaml).to include("dos-release", "gitea_token")
    expect(yaml).not_to include("scripts/ci-")
  end

  it "adds the store step from the host's store settings, with the marker's secret" do
    yaml = render(config_class, { store: store }, options: { "store_secret" => "store_ssh_key" })
    jobs = jobs_of.call(YAML.safe_load(yaml))

    expect(jobs.keys.last).to eq("store")
    expect(yaml).to include("registry.example/deploy-ssh:1", "deploy@store.example", "store.example ssh-ed25519 AAAA", "store_ssh_key")
  end

  it "falls back to deploy_ssh_key and ignores options that are not plain words" do
    yaml = render(config_class, { store: store }, options: { "store_secret" => "x; rm -rf /" })

    expect(yaml).to include("deploy_ssh_key")
    expect(yaml).not_to include("x; rm")
  end

  it "runs the builder image's commands and no script of the repo's own" do
    yaml = render(config_class, { store: store })

    expect(yaml).to include("dos-check", "dos-build", "dos-test", "dos-pack", "tar -C dist/store")
    expect(yaml).not_to include("scripts/ci-")
  end

  it "uploads the program folder and the Win32 folder under WarpEngine names" do
    yaml = render(config_class, {})

    expect(yaml).to include("dosinst-$VERSION.zip", "dosinst-$VERSION-win-x86.zip", "dosinst-$VERSION.metadata.json",
                            "platform=dos&version=$VERSION")
  end
end

RSpec.describe WarpEngine::CI::Woodpecker::PipelineConfig do
  include_examples "dos pipeline", described_class,
                   ->(pipeline) { pipeline["steps"].to_h { |step| [ step["name"], step ] } }

  it "runs everything but the tests on tags only" do
    steps = YAML.safe_load(described_class.new(platforms: { "dos" => { builder: "b", forge_release: true } })
                                          .render(platform: "dos", name: "x", update_server: "u"))["steps"]

    expect(steps.reject { |step| step["name"] == "test" }.map { |step| step["when"] }.uniq).to eq([ [ { "event" => "tag" } ] ])
    expect(steps.first["when"]).to be_nil
  end
end

RSpec.describe WarpEngine::CI::Gitlab::PipelineConfig do
  include_examples "dos pipeline", described_class,
                   ->(pipeline) { pipeline.select { |_, job| job.is_a?(Hash) && job["image"] } }
end
