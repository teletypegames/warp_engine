require "rails_helper"
require "open3"

# A platform service in the pre-1.12 form, for the legacy template path.
class LegacyAmigaService
  include WarpEngine::Platforms::Updatable
  include WarpEngine::Platforms::Builds::BuildWeb

  platform "amiga"
  required_kinds "html"
end

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
      clean = %w[CI_COMMIT_TAG CI_COMMIT_SHA CI_COMMIT_BRANCH CI_COMMIT_SOURCE_BRANCH CI_MERGE_REQUEST_SOURCE_BRANCH_NAME
                 CI_REPO_DEFAULT_BRANCH CI_DEFAULT_BRANCH].to_h { |key| [ key, nil ] }
      output, status = Open3.capture2e(clean.merge(env), "sh", "-c", script, chdir: dir)
      [ status.success? ? File.read(File.join(dir, ".version")).strip : nil, output ]
    end
  end

  adapters.each do |config_class, step_names|
    describe config_class do
      WarpEngine::Platform::NAMES.each do |platform|
        it "starts the #{platform} pipeline with the shared version step and names its upload step upload" do
          names = step_names.call(YAML.safe_load(render(config_class, platform)))

          expect(names.first).to eq("version")
          expect(names.count("version")).to eq(1)
          expect(names).to include("upload", "publish")
          expect(names).not_to include("artifact", "store")
        end

        it "tags the #{platform} build after the release steps" do
          names = step_names.call(YAML.safe_load(render(config_class, platform)))

          expect(names.last).to eq("tag")
          expect(names.index("tag")).to be > names.index("publish")
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

        it "takes the repo's default branch for the main one when the CI names it" do
          develop = { "CI_COMMIT_BRANCH" => "develop", "CI_REPO_DEFAULT_BRANCH" => "develop", "CI_DEFAULT_BRANCH" => "develop" }
          master  = { "CI_COMMIT_BRANCH" => "master", "CI_REPO_DEFAULT_BRANCH" => "develop", "CI_DEFAULT_BRANCH" => "develop" }

          expect(run_version(script, develop, metadata).first).to eq("1.2.0")
          expect(run_version(script, master, metadata).first).to eq("dev-1.2.0-master")
        end

        it "is a dev version of the tagged commit on a dev tag" do
          sha = { "CI_COMMIT_SHA" => "abcdef0123456789" }

          expect(run_version(script, sha.merge("CI_COMMIT_TAG" => "dev-feature-x"), metadata).first).to eq("dev-1.2.0-feature-x")
          expect(run_version(script, sha.merge("CI_COMMIT_TAG" => "dev-master")).first).to eq("dev-abcdef0")
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
          WarpEngine.config.register_platform("amiga", version_source: "cat VERSION") { kind :html, required: true }
          config = config_class.new(platforms: { "amiga" => { builder: "b" } })

          expect(config.version_source("amiga")).to eq("cat VERSION")
        ensure
          WarpEngine.config.platforms.delete("amiga")
        end
      end
    end
  end

  it "leaves the CI's own variables the only ${...} in the shared steps, which Woodpecker substitutes before the shell runs" do
    config = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "godot" => { builder: "b", forge_release: true } })
    document = YAML.safe_load(config.render(platform: "godot", name: "game", update_server: "u"))
    shared = document["steps"].select { |step| %w[version tag release].include?(step["name"]) }.flat_map { |step| step["commands"] }.join("\n")

    expect(shared.scan(/\$\{(\w+)/).flatten.uniq -
           %w[CI_COMMIT_TAG CI_COMMIT_SHA CI_COMMIT_SOURCE_BRANCH CI_COMMIT_BRANCH CI_REPO_DEFAULT_BRANCH]).to eq([])
  end

  describe "the tag step" do
    forges = {
      WarpEngine::CI::Woodpecker::PipelineConfig => {
        env:    { "CI_FORGE_URL" => "https://forge.example/", "CI_REPO" => "games/game", "GITEA_TOKEN" => "t" },
        script: ->(document) { document["steps"].find { |step| step["name"] == "tag" }["commands"].join("\n") },
        found:  ->(sha) { %({"name":"x","id":"1111","commit":{"url":"https://forge.example/c","sha":"#{sha}","created":"x"}}) }
      },
      WarpEngine::CI::Gitlab::PipelineConfig => {
        env:    { "CI_API_V4_URL" => "https://gitlab.example/api/v4", "CI_PROJECT_ID" => "7", "TAG_TOKEN" => "t" },
        script: ->(document) { document["tag"]["script"].join("\n") },
        found:  ->(sha) { %({"name":"x","commit":{"id":"#{sha}","short_id":"abc","title":"x"},"release":null}) }
      }
    }

    # A curl that answers the tag lookup with the given body and logs every call.
    def run_tag(script, env, version:, lookup:)
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".version"), version)
        File.write(File.join(dir, "lookup"), lookup)
        File.write(File.join(dir, "curl"), <<~SH)
          #!/bin/sh
          case "$*" in
            *POST*) echo "$* $(cat)" >> "#{dir}/calls" ;;
            *DELETE*) echo "$*" >> "#{dir}/calls" ;;
            *) echo "$*" >> "#{dir}/calls"; cat "#{dir}/lookup" ;;
          esac
        SH
        File.chmod(0o755, File.join(dir, "curl"))
        _, status = Open3.capture2e({ "PATH" => "#{dir}:#{ENV.fetch('PATH')}" }.merge(env), "sh", "-c", script, chdir: dir)
        raise "the tag step failed" unless status.success?

        File.exist?(File.join(dir, "calls")) ? File.readlines(File.join(dir, "calls"), chomp: true) : []
      end
    end

    forges.each do |config_class, forge|
      describe config_class do
        let(:script) { forge[:script].call(YAML.safe_load(render(config_class, "godot"))) }
        let(:env) { forge[:env].merge("CI_COMMIT_SHA" => "aaaa1111", "CI_COMMIT_BRANCH" => "feature/x") }

        it "tags a new version" do
          calls = run_tag(script, env, version: "1.2.0", lookup: %({"message":"not found"}))

          expect(calls.last).to include("POST").and include("v1.2.0")
          expect(calls.grep(/DELETE/)).to be_empty
        end

        it "leaves a version that is tagged already alone" do
          calls = run_tag(script, env, version: "1.2.0", lookup: forge[:found].call("bbbb2222"))

          expect(calls.grep(/POST|DELETE/)).to be_empty
        end

        it "moves the branch's dev tag onto the commit" do
          calls = run_tag(script, env, version: "dev-1.2.0-feature-x", lookup: forge[:found].call("bbbb2222"))

          expect(calls.grep(/DELETE/).first).to include("dev-feature-x")
          expect(calls.last).to include("POST").and include("dev-feature-x").and include("aaaa1111")
        end

        it "does not move a dev tag that is on the commit already" do
          calls = run_tag(script, env, version: "dev-1.2.0-feature-x", lookup: forge[:found].call("aaaa1111"))

          expect(calls.grep(/POST|DELETE/)).to be_empty
        end
      end
    end
  end

  it "starts a Woodpecker pipeline on every event but release, and leaves a template's own filter alone" do
    document = YAML.safe_load(render(WarpEngine::CI::Woodpecker::PipelineConfig, "godot"))

    expect(document["when"]).to eq([ { "event" => %w[push pull_request pull_request_closed pull_request_metadata tag deployment
                                                     cron manual] } ])
    expect(YAML.safe_load(render(WarpEngine::CI::Gitlab::PipelineConfig, "godot"))).not_to have_key("when")

    config = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "amiga" => { builder: "b" } })
    Dir.mktmpdir do |dir|
      template = File.join(dir, "amiga.yaml.erb")
      File.write(template, "when:\n  - event: tag\nsteps:\n  - name: build\n    image: b\n    commands: [ make ]\n")
      WarpEngine.config.register_platform("amiga", service: "LegacyAmigaService", templates: { woodpecker: template })

      expect(YAML.safe_load(config.render(platform: "amiga", name: "x", update_server: "u"))["when"]).to eq([ { "event" => "tag" } ])
    end
  ensure
    WarpEngine.config.platforms.delete("amiga")
  end

  it "makes no forge release of a dev tag" do
    [ WarpEngine::CI::Woodpecker::PipelineConfig, WarpEngine::CI::Gitlab::PipelineConfig ].each do |config_class|
      expect(render(config_class, "godot", spec: { forge_release: true })).to include('case "$CI_COMMIT_TAG" in dev-*)')
    end
  end

  it "attaches a build's own list when it writes .release-assets, and the uploaded files otherwise" do
    yaml = render(WarpEngine::CI::Woodpecker::PipelineConfig, "godot", spec: { forge_release: true })

    expect(yaml).to include(".release-assets", "NAME='game'", '"$NAME-$VERSION.*"', "RELEASE_NOTES.md", "gitea_token", "CI_FORGE_URL")
  end

  it "makes a GitLab release with the job token" do
    yaml = render(WarpEngine::CI::Gitlab::PipelineConfig, "godot", spec: { forge_release: true })

    expect(yaml).to include("JOB-TOKEN", "packages/generic", "/releases")
    expect(yaml).not_to include("gitea_token")
  end
end
