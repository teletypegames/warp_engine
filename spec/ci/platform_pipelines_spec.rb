require "rails_helper"
require_relative "../support/pipeline_helpers"

RSpec.describe "Every platform's pipeline" do
  include PipelineHelpers

  ci_variables = %w[CI_COMMIT_TAG CI_COMMIT_SHA CI_COMMIT_SOURCE_BRANCH CI_COMMIT_BRANCH CI_REPO_DEFAULT_BRANCH
                    CI_MERGE_REQUEST_SOURCE_BRANCH_NAME CI_DEFAULT_BRANCH]
  builder = "registry.example/builder:latest"
  exporter = "registry.example/exporter:latest"

  [ WarpEngine::CI::Woodpecker::PipelineConfig, WarpEngine::CI::Gitlab::PipelineConfig ].each do |config_class|
    WarpEngine::Platform::NAMES.each do |name|
      platform = WarpEngine::Platform.find(name)
      (platform.apps.presence || [ nil ]).each do |app|
        variant = platform.for_app(app) if app
        variant ||= platform

        describe "#{config_class.name.demodulize} #{[ name, app ].compact.join('/')}" do
          let(:yaml) do
            config_class.new(platforms: { name => { builder: builder, exporter: exporter } })
                        .render(platform: name, name: "game", update_server: "https://games.example", options: app ? { "app" => app } : {})
          end
          let(:commands) { yaml }

          it "renders a pipeline" do
            expect(yaml).to be_present
            expect { YAML.safe_load(yaml) }.not_to raise_error
          end

          it "leaves the CI's own variables the only ${...}, which Woodpecker would substitute" do
            expect(yaml.scan(/\$\{(\w+)/).flatten.uniq - ci_variables).to eq([])
          end

          it "packs every native kind it builds with warp_target, in the mode of its kind spec" do
            variant.kind_specs.select { |spec| spec.built && spec.name.match?(WarpEngine::CI::PipelineConfig::NATIVE_KIND) }.each do |spec|
              mode = if spec.required then "required" elsif spec.optional then "optional" else "expected" end
              next if %w[c64 plus4 dos].include?(name)

              expect(yaml).to include("warp_target '#{spec.upload_suffix}' #{mode}"), "#{name}: #{spec.name} is not packed as #{mode}"
            end
          end

          it "speaks English in its messages" do
            expect(yaml).not_to match(/\bkesz\b/)
          end
        end
      end
    end
  end

  describe "the Woodpecker steps" do
    WarpEngine::Platform::NAMES.each do |name|
      it "pulls the builder and exporter images on every #{name} run" do
        yaml = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { name => { builder: builder, exporter: exporter } })
                                                       .render(platform: name, name: "game", update_server: "u")
        YAML.safe_load(yaml)["steps"].select { |step| [ builder, exporter ].include?(step["image"]) }.each do |step|
          expect(step["pull"]).to be(true), "#{name}/#{step['name']}: not pulled"
        end
      end
    end
  end

  describe "the check step" do
    let(:yaml) do
      WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "godot" => { builder: builder } })
                                              .render(platform: "godot", name: "game", update_server: "u")
    end

    it "runs after the version, in the builder image" do
      steps = YAML.safe_load(yaml)["steps"]

      expect(steps.map { |step| step["name"] }.first(2)).to eq(%w[version check])
      expect(steps[1]).to include("image" => builder, "pull" => true)
    end

    it "runs make check when the Makefile has that target, and passes without one" do
      skip "no make here" unless system("command -v make >/dev/null 2>&1")
      script = step_script(yaml, "check")

      _, status = run_with_fake_curl(script, files: { "Makefile" => "check:\n\tfalse\n" })
      expect(status).not_to be_success
      _, status = run_with_fake_curl(script, files: { "Makefile" => "check:\n\ttrue\n" })
      expect(status).to be_success
      _, status = run_with_fake_curl(script, files: { "Makefile" => "build:\n\ttrue\n" })
      expect(status).to be_success
      _, status = run_with_fake_curl(script)
      expect(status).to be_success
    end
  end

  describe "warp_target" do
    let(:pack) { WarpEngine::CI::Scripts.assign(NAME: "game") + WarpEngine::CI::Scripts.read("pack") }

    def run(body, files = {})
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".version"), "1.0")
        files.each { |file, content| File.write(File.join(dir, file), content) }
        output, status = Open3.capture2e("sh", "-c", "set -e\n#{pack}\n#{body}", chdir: dir)
        [ output, status, Dir.children(dir).sort ]
      end
    end

    it "zips the target with one root folder and the repository's LICENSE and README" do
      skip "no zip here" unless system("command -v zip unzip >/dev/null 2>&1")
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".version"), "1.0")
        File.write(File.join(dir, "LICENSE"), "MIT")
        File.write(File.join(dir, "README.md"), "hi")
        _, status = Open3.capture2e("sh", "-c", "set -e\n#{pack}\nbuild() { echo x > \"$PKG_DIR/game\"; }\nwarp_target -linux-x64.zip required build", chdir: dir)

        expect(status).to be_success
        listing, = Open3.capture2("unzip", "-Z1", File.join(dir, "game-1.0-linux-x64.zip"))
        expect(listing.split("\n")).to contain_exactly("game-1.0-linux-x64/", "game-1.0-linux-x64/game",
                                                       "game-1.0-linux-x64/LICENSE", "game-1.0-linux-x64/README.md")
      end
    end

    it "stops at the first failing command of the build function" do
      output, status, = run("build() { false; echo reached > \"$PKG_DIR/x\"; }\nwarp_target -win-x64.zip expected build")

      expect(status).not_to be_success
      expect(output).to include("game-1.0-win-x64.zip is expected and does not build")
    end

    it "leaves an optional target out with a warning and goes on" do
      output, status, files = run("build() { false; }\nwarp_target -mac-x64-cli.zip optional build\necho after")

      expect(status).to be_success
      expect(output).to include("WARNING: game-1.0-mac-x64-cli.zip does not build", "after")
      expect(files).not_to include("game-1.0-mac-x64-cli", "game-1.0-mac-x64-cli.zip")
    end
  end

  describe "marker options" do
    let(:config) { WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "c64" => { builder: builder, exporter: exporter } }) }

    it "keeps a declared option's allowed value and drops any other" do
      expect(config.render(platform: "c64", name: "game", update_server: "u", options: { "media" => "d64" })).to include("make game.d64")
      expect(config.render(platform: "c64", name: "game", update_server: "u", options: { "media" => "tap" })).to include("acme -f cbm")
    end
  end
end
