require "rails_helper"
require_relative "../support/pipeline_helpers"

RSpec.describe "store engine pipelines" do
  %w[batocera retroarch].each do |host|
    describe host do
      def render(host)
        WarpEngine::CI::Woodpecker::PipelineConfig
          .new(platforms: { host => { builder: "registry.example/store-engine-builder:1", tools: "registry.example/ci-tools:1" } })
          .render(platform: host, name: "we-#{host}", update_server: "https://games.example")
      end

      it "tests and packs with the repository's scripts, and releases on tags" do
        yaml = render(host)
        steps = YAML.safe_load(yaml)["steps"].to_h { |step| [ step["name"], step ] }

        expect(steps.keys).to eq(%w[version test package upload publish tag])
        expect(yaml).to include("sh scripts/ci-test.sh", "sh scripts/pack.sh", "PLATFORM='#{host}'")
        expect(steps.values_at("package", "upload", "publish").map { |step| step["when"] }).to all(eq([ { "event" => "tag" } ]))
      end

      it "uploads the packed archive under the release name" do
        yaml = render(host)
        skip "the upload's prepare lines need jq" unless system("command -v jq >/dev/null 2>&1")

        files = { "metadata.json" => %({"name": "we-#{host}"}), "dist/release.tar.gz" => "archive" }
        calls, status = run_with_fake_curl(step_script(yaml, "upload"), files: files, version: "1.3.0")

        expect(status).to be_success
        expect(uploaded_files(calls)).to contain_exactly("we-#{host}-1.3.0.tar.gz", "we-#{host}-1.3.0.metadata.json")
      end
    end
  end
end
