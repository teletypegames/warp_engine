require "rails_helper"

shared_examples "pipeline config tools image" do |config_class, steps_of|
  installs = /apk add|luarocks install|ln -sf \/usr\/bin\/lua/

  def self.render(config_class, platform, tools)
    spec = { builder: "registry.example/builder:1", exporter: "registry.example/exporter:1" }
    spec[:tools] = tools if tools
    config_class.new(platforms: { platform => spec })
                .render(platform: platform, name: "example", update_server: "https://games.example")
  end

  WarpEngine::Platform::NAMES.each do |platform|
    context platform do
      it "runs the helper steps in the tools image, with nothing to install" do
        yaml = self.class.render(config_class, platform, "registry.example/ci-tools:1")
        steps = steps_of.call(YAML.safe_load(yaml))

        expect(yaml).not_to match(installs)
        expect(steps.map { |step| step["image"] }).not_to include("alpine")
        expect(steps.map { |step| step["image"] }).to include("registry.example/ci-tools:1")
        steps.each { |step| expect(step["commands"] || step["script"]).to be_present, "#{platform}: empty step" }
      end

      it "installs what the helper steps need into alpine without a tools image" do
        yaml = self.class.render(config_class, platform, nil)

        expect(steps_of.call(YAML.safe_load(yaml)).map { |step| step["image"] }).to include("alpine")
        expect(yaml).to match(installs)
      end
    end
  end
end

RSpec.describe WarpEngine::CI::Woodpecker::PipelineConfig do
  include_examples "pipeline config tools image", described_class, ->(pipeline) { pipeline["steps"] }
end

RSpec.describe WarpEngine::CI::Gitlab::PipelineConfig do
  include_examples "pipeline config tools image", described_class,
                   ->(pipeline) { pipeline.values.select { |job| job.is_a?(Hash) && job["image"] } }
end
