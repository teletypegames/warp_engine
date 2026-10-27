require "rails_helper"

RSpec.describe "Generated pipeline options" do
  def render(config_class, platform, spec: {}, options: {})
    config_class.new(platforms: { platform => { builder: "registry.example/builder:1", exporter: "registry.example/exporter:1" }.merge(spec) })
                .render(platform: platform, name: "game", update_server: "https://games.example", options: options)
  end

  describe "release: tag" do
    it "runs the Woodpecker release steps on tags only and leaves the build to every event" do
      steps = YAML.safe_load(render(WarpEngine::CI::Woodpecker::PipelineConfig, "c64", options: { "release" => "tag" }))["steps"]
      by_name = steps.to_h { |step| [ step["name"], step ] }

      expect(by_name.values_at("package", "upload", "publish").map { |step| step["when"] }).to all(eq([ { "event" => "tag" } ]))
      expect(by_name.values_at("version", "build").map { |step| step["when"] }).to all(be_nil)
    end

    it "puts the GitLab release jobs behind a tag rule" do
      document = YAML.safe_load(render(WarpEngine::CI::Gitlab::PipelineConfig, "godot", options: { "release" => "tag" }))

      expect(document.values_at("upload", "publish").map { |job| job["rules"] }).to all(eq([ { "if" => "$CI_COMMIT_TAG" } ]))
      expect(document["build"]["rules"]).to be_nil
    end

    it "publishes on every push by default, and ignores a rule it does not know" do
      config = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "c64" => { builder: "b" } })

      expect(config.release_rule("c64", {})).to eq("push")
      expect(config.release_rule("c64", { "release" => "nightly" })).to eq("push")
      expect(render(WarpEngine::CI::Woodpecker::PipelineConfig, "c64", options: { "release" => "push" }))
        .to eq(render(WarpEngine::CI::Woodpecker::PipelineConfig, "c64"))
    end

    it "keeps DOS on tags whatever the marker says" do
      config = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "dos" => { builder: "b" } })

      expect(config.release_rule("dos", { "release" => "push" })).to eq("tag")
    end
  end

  [ WarpEngine::CI::Woodpecker::PipelineConfig, WarpEngine::CI::Gitlab::PipelineConfig ].each do |config_class|
    describe "#{config_class} host values" do
      %w[bevy ebitengine phaser].each do |platform|
        it "takes the #{platform} web shell from the host, or the repo's web/index.html" do
          expect(render(config_class, platform, spec: { web_shell: "https://shell.example/index.html" }))
            .to include("curl -sSL https://shell.example/index.html")
          expect(render(config_class, platform)).to include("cp web/index.html")
          expect(render(config_class, platform)).not_to include("teletypegames")
        end
      end

      it "names the LÖVE mac bundle with the host's prefix" do
        expect(render(config_class, "love", spec: { bundle_id_prefix: "com.example" })).to include("com.example.game")
        expect(render(config_class, "love")).to include("org.warpengine.game")
      end
    end
  end
end
