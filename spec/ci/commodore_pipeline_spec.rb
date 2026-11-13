require "rails_helper"
require_relative "../support/pipeline_helpers"

RSpec.describe "Commodore pipelines" do
  [ WarpEngine::CI::Woodpecker::PipelineConfig, WarpEngine::CI::Gitlab::PipelineConfig ].product(%w[c64 plus4]).each do |config_class, platform|
    describe "#{config_class} #{platform}" do
      define_method(:render) do |config_class, options = {}|
        config_class.new(platforms: { platform => { builder: "registry.example/builder:1", exporter: "registry.example/commodore-player:1" } })
                    .render(platform: platform, name: "warp64u", update_server: "https://games.example", options: options)
      end

      it "assembles main.asm with ACME by default" do
        yaml = render(config_class)

        expect(yaml).to include("acme -f cbm -o warp64u.prg main.asm")
        expect(yaml).not_to include("make warp64u.prg")
        expect { YAML.safe_load(yaml) }.not_to raise_error
      end

      it "leaves the build to the repo's Makefile when the marker says build: make" do
        yaml = render(config_class, { "build" => "make" })

        expect(yaml).to include("make warp64u.prg", "cp warp64u.prg warp64u-$VERSION.prg", "commodore-pack #{platform} warp64u $VERSION")
        expect(yaml).not_to include("acme")
        expect { YAML.safe_load(yaml) }.not_to raise_error
      end

      it "uploads the program and its metadata always, and the players only when they were built" do
        script = step_script(render(config_class), "upload")
        program = { "warp64u-1.0.prg" => "prg", "metadata.json" => "{}" }

        calls, status = run_with_fake_curl(script, files: program, env: { "UPDATE_SERVER" => "https://games.example" })
        expect(status).to be_success
        expect(uploaded_files(calls)).to contain_exactly("warp64u-1.0.prg", "warp64u-1.0.metadata.json")
        expect(calls.first).to include("https://games.example/build/upload?name=warp64u&version=1.0")

        calls, = run_with_fake_curl(script, files: program.merge("warp64u-1.0.html.zip" => "z", "warp64u-1.0-win-x64.zip" => "z"))
        expect(uploaded_files(calls)).to contain_exactly("warp64u-1.0.prg", "warp64u-1.0.metadata.json",
                                                         "warp64u-1.0.html.zip", "warp64u-1.0-win-x64.zip")
      end

      it "fails the upload without the program, the kind the platform requires" do
        _, status = run_with_fake_curl(step_script(render(config_class), "upload"), files: { "metadata.json" => "{}" })

        expect(status).not_to be_success
      end

      it "publishes the build under its own platform" do
        calls, = run_with_fake_curl(step_script(render(config_class), "publish"), env: { "UPDATE_SERVER" => "https://u.example" })

        expect(calls.last).to end_with("https://u.example/build/publish?name=warp64u&platform=#{platform}&version=1.0")
      end
    end
  end
end
