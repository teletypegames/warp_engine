require "rails_helper"
require_relative "../support/pipeline_helpers"

RSpec.describe "The electron pipeline" do
  def render(options: {})
    WarpEngine::CI::Woodpecker::PipelineConfig
      .new(platforms: { "electron" => { builder: "registry.example/electron-builder:1", tools: "registry.example/ci-tools:1" } })
      .render(platform: "electron", name: "mystore", update_server: "https://games.example", options: options)
  end

  let(:yaml) { render }
  let(:steps) { YAML.safe_load(yaml)["steps"].to_h { |step| [ step["name"], step ] } }

  it "builds Linux, then Windows, in the builder image, then uploads, publishes and tags" do
    expect(steps.keys).to eq(%w[version linux windows upload publish tag])
    expect(steps.values_at("linux", "windows").map { |step| step["image"] }).to all(eq("registry.example/electron-builder:1"))
  end

  it "runs the app's own build and packages with the project's electron-builder" do
    expect(yaml).to include("npm run check --if-present", "npm run build --if-present", "npx --no-install electron-builder --linux AppImage --x64",
                            "electron-builder --win nsis --x64", "mystore-$VERSION-linux-x64", "mystore-$VERSION-win-x64")
  end

  it "reads the version from package.json" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "package.json"), %({\n  "name": "mystore",\n  "version": "3.4.0",\n  "dependencies": {}\n}\n))
      version = IO.popen([ "sh", "-c", WarpEngine::Platform.find("electron").version_source ], chdir: dir, &:read)

      expect(version.strip).to eq("3.4.0")
    end
  end

  it "uploads the Linux zip always, the Windows zip when there is one, and the metadata" do
    calls, status = run_with_fake_curl(step_script(yaml, "upload"),
                                       files: { "metadata.json" => %({"name": "mystore"}),
                                                "mystore-3.4.0-linux-x64.zip" => "linux" },
                                       version: "3.4.0")

    expect(status).to be_success
    expect(uploaded_files(calls)).to contain_exactly("mystore-3.4.0-linux-x64.zip", "mystore-3.4.0.metadata.json")
  end

  it "expects the macOS kinds without building them" do
    platform = WarpEngine::Platform.find("electron")

    expect(platform.kind_specs.reject(&:built).map { |spec| spec.kind.name }).to eq(%w[mac_x64 mac_arm64])
  end
end
