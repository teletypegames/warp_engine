require "rails_helper"
require "open3"

RSpec.describe "Steps every generated pipeline shares" do
  adapters = {
    WarpEngine::CI::Woodpecker::PipelineConfig => ->(document) { document["steps"].map { |step| step["name"] } },
    WarpEngine::CI::Gitlab::PipelineConfig     => ->(document) { document["stages"] }
  }

  def render(config_class, platform, spec: {}, options: {})
    config_class.new(platforms: { platform => { builder: "registry.example/builder:1", exporter: "registry.example/exporter:1",
                                                tools: "registry.example/tools:1" }.merge(spec) })
                .render(platform: platform, name: "game", update_server: "https://games.example", options: options)
  end

  def version_script(document)
    step = document["steps"]&.find { |candidate| candidate["name"] == "version" }
    (step ? step["commands"] : document["version"]["script"]).join("\n")
  end

  def run_version(script, env, files = {})
    Dir.mktmpdir do |dir|
      files.each { |name, content| FileUtils.mkdir_p(File.dirname(File.join(dir, name))) && File.write(File.join(dir, name), content) }
      clean = %w[CI_COMMIT_TAG CI_COMMIT_SHA CI_COMMIT_BRANCH CI_COMMIT_SOURCE_BRANCH CI_MERGE_REQUEST_SOURCE_BRANCH_NAME].to_h { |key| [ key, nil ] }
      output, status = Open3.capture2e(clean.merge(env), "sh", "-c", script, chdir: dir)
      [ status.success? ? File.read(File.join(dir, ".version")).strip : nil, output ]
    end
  end

  adapters.each do |config_class, step_names|
    describe config_class do
      WarpEngine::CI::PipelineConfig::BUILT_KINDS.each_key do |platform|
        it "starts the #{platform} pipeline with the shared version step and names its upload step upload" do
          names = step_names.call(YAML.safe_load(render(config_class, platform)))

          expect(names.first).to eq("version")
          expect(names.count("version")).to eq(1)
          expect(names).to include("upload", "publish")
          expect(names).not_to include("artifact", "store")
        end

        it "ends the #{platform} pipeline with a forge release only when the host asks for one" do
          expect(step_names.call(YAML.safe_load(render(config_class, platform)))).not_to include("release")
          expect(step_names.call(YAML.safe_load(render(config_class, platform, spec: { forge_release: true }))).last).to eq("release")
        end
      end

      describe "the version" do
        let(:script) { version_script(YAML.safe_load(render(config_class, "godot"))) }
        let(:metadata) { { "metadata.json" => %({"name": "game", "version": "1.2.0"}) } }

        it "comes from metadata.json on the main branch" do
          expect(run_version(script, { "CI_COMMIT_BRANCH" => "master" }, metadata).first).to eq("1.2.0")
        end

        it "is a dev version on another branch" do
          expect(run_version(script, { "CI_COMMIT_BRANCH" => "feature/x" }, metadata).first).to eq("dev-1.2.0-feature-x")
        end

        it "has to match a version tag" do
          expect(run_version(script, { "CI_COMMIT_TAG" => "v1.2.0" }, metadata).first).to eq("1.2.0")
          version, output = run_version(script, { "CI_COMMIT_TAG" => "v1.3.0" }, metadata)
          expect(version).to be_nil
          expect(output).to include("does not match")
        end

        it "ignores a tag that is not a version" do
          expect(run_version(script, { "CI_COMMIT_TAG" => "jam-final" }, metadata).first).to eq("1.2.0")
        end

        it "is the tag's when the source names none, and a dev build of the commit when there is no tag either" do
          expect(run_version(script, { "CI_COMMIT_TAG" => "v0.6.1" }).first).to eq("0.6.1")
          expect(run_version(script, { "CI_COMMIT_SHA" => "abcdef0123456789", "CI_COMMIT_BRANCH" => "master" }).first).to eq("dev-abcdef0")
        end

        it "comes from the Lua header on TIC-80" do
          tic = version_script(YAML.safe_load(render(config_class, "tic80")))

          expect(run_version(tic, { "CI_COMMIT_BRANCH" => "main" }, { "inc/meta/meta.header.lua" => "-- title: x\n-- version: 0.4.2\n" }).first)
            .to eq("0.4.2")
        end

        it "takes a registered platform's own source" do
          WarpEngine.config.register_platform("amiga", service: "WarpEngine::Platforms::Phaser::Service", version_source: "cat VERSION")
          config = config_class.new(platforms: { "amiga" => { builder: "b" } })

          expect(config.version_source("amiga")).to eq("cat VERSION")
        ensure
          WarpEngine.config.platforms.delete("amiga")
        end
      end
    end
  end

  it "attaches a build's own list when it writes .release-assets, and the uploaded files otherwise" do
    yaml = render(WarpEngine::CI::Woodpecker::PipelineConfig, "godot", spec: { forge_release: true })

    expect(yaml).to include(".release-assets", 'game-$VERSION.*', "RELEASE_NOTES.md", "gitea_token", "CI_FORGE_URL")
  end

  it "makes a GitLab release with the job token" do
    yaml = render(WarpEngine::CI::Gitlab::PipelineConfig, "godot", spec: { forge_release: true })

    expect(yaml).to include("JOB-TOKEN", "packages/generic", "/releases")
    expect(yaml).not_to include("gitea_token")
  end
end
