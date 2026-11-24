require "rails_helper"
require_relative "../support/pipeline_helpers"

RSpec.describe "Go docs in the pipelines" do
  required = { "ebitengine" => "game-1.0.html.zip", "golang:cli" => "game-1.0-linux-x64-cli.zip", "golang:gui" => "game-1.0-linux-x64.zip" }

  [ WarpEngine::CI::Woodpecker::PipelineConfig, WarpEngine::CI::Gitlab::PipelineConfig ].product(required.keys).each do |config_class, key|
    platform, app = key.split(":")

    describe "#{config_class} #{key}" do
      define_method(:render) do
        options = app ? { "app" => app } : {}
        config_class.new(platforms: { platform => { builder: "registry.example/builder:1" } })
                    .render(platform: platform, name: "game", update_server: "https://games.example", options: options)
      end

      it "writes the docs with doc2go in the builder image" do
        script = step_script(render, "docs")

        expect(script).to include("warp_godoc() {", "doc2go", "NAME='game'")
        expect(script.lines.last.strip).to eq("warp_godoc")
      end

      it "writes no docs and does not fail without a Go module" do
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, ".version"), "1.0")
          output, status = Open3.capture2e("sh", "-c", step_script(render, "docs"), chdir: dir)

          expect(status).to be_success
          expect(output).to include("No Go module: no docs")
        end
      end

      it "uploads the docs when the build made them" do
        files = { required.fetch(key) => "z", "game-1.0-docs.zip" => "z", "metadata.json" => "{}" }
        calls, status = run_with_fake_curl(step_script(render, "upload"), files: files)

        expect(status).to be_success
        expect(uploaded_files(calls)).to include("game-1.0-docs.zip", required.fetch(key))
      end
    end
  end
end
