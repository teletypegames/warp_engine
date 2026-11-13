require "rails_helper"
require_relative "../support/pipeline_helpers"

shared_examples "dos pipeline" do |config_class, jobs_of|
  def render(config_class, spec, options: {})
    config_class.new(platforms: { "dos" => { builder: "registry.example/dos-builder:1", tools: "registry.example/ci-tools:1" }.merge(spec) })
                .render(platform: "dos", name: "dosinst", update_server: "https://games.example", options: options)
  end

  it "tests, packs, uploads and publishes, tags after a push, and has no store step of its own" do
    yaml = render(config_class, {})
    jobs = jobs_of.call(YAML.safe_load(yaml))

    expect(jobs.keys).to eq(%w[version test package upload publish tag])
    expect(yaml).not_to include("ssh", "dist/store", "store_secret")
  end

  it "adds the forge release when the host asks for it" do
    jobs = jobs_of.call(YAML.safe_load(render(config_class, { forge_release: true })))

    expect(jobs.keys.last).to eq("release")
  end

  it "runs the builder image's commands and no script of the repo's own" do
    yaml = render(config_class, {})

    expect(yaml).to include("dos-check", "dos-build", "dos-test", "dos-pack")
    expect(yaml).not_to include("scripts/ci-", "dos-release")
  end

  it "uploads the program folder and the Win32 folder under WarpEngine names, with the dos block kept for the shelf" do
    yaml = render(config_class, {})
    metadata = %({"name": "dosinst", "dos": {"folder": "DOSINST", "win32_folder": "DOSINSTW"}})
    files = { "metadata.json" => metadata, "dist/DOSINST-v0.6.0.zip" => "dos", "dist/DOSINSTW-v0.6.0.zip" => "win32" }

    calls, status = run_with_fake_curl(step_script(yaml, "upload"), files: files, version: "0.6.0",
                                                                    env: { "CI_COMMIT_TAG" => "v0.6.0" })

    expect(status).to be_success
    expect(uploaded_files(calls)).to contain_exactly("dosinst-0.6.0.zip", "dosinst-0.6.0-win-x86.zip", "dosinst-0.6.0.metadata.json")
    expect(yaml).to include("'. + {version: $version}'", "PLATFORM='dos'")
    expect(yaml).not_to include("del(.dos)")
  end
end

RSpec.describe WarpEngine::CI::Woodpecker::PipelineConfig do
  include_examples "dos pipeline", described_class,
                   ->(pipeline) { pipeline["steps"].to_h { |step| [ step["name"], step ] } }

  it "runs everything but the version and the tests on tags only" do
    steps = YAML.safe_load(described_class.new(platforms: { "dos" => { builder: "b", forge_release: true } })
                                          .render(platform: "dos", name: "x", update_server: "u"))["steps"]
    by_name = steps.to_h { |step| [ step["name"], step["when"] ] }

    expect(by_name.values_at("package", "upload", "publish", "release")).to all(eq([ { "event" => "tag" } ]))
    expect(by_name.values_at("version", "test")).to all(be_nil)
    expect(by_name["tag"]).to eq([ { "event" => %w[push manual] } ])
  end
end

RSpec.describe WarpEngine::CI::Gitlab::PipelineConfig do
  include_examples "dos pipeline", described_class,
                   ->(pipeline) { pipeline.select { |_, job| job.is_a?(Hash) && job["image"] } }

  it "lists the version stage first and the release stage last" do
    document = YAML.safe_load(described_class.new(platforms: { "dos" => { builder: "b", forge_release: true } })
                                             .render(platform: "dos", name: "x", update_server: "u"))

    expect(document["stages"]).to eq(%w[version test package upload publish tag release])
    expect(document.keys.first(2)).to eq(%w[stages version])
  end
end
