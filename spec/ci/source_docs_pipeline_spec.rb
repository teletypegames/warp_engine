require "rails_helper"
require_relative "../support/pipeline_helpers"

RSpec.describe "Source docs of the dos, electron, love and bevy pipelines" do
  cases = {
    "dos" => { call: "warp_cdoc c++ SOURCE '*.cpp' '*.h'", helper: "warp_cdoc() {", image: "registry.example/ci-tools:1",
               skip: "No sources under SOURCE/: no docs" },
    "electron" => { call: "warp_tsdoc", helper: "warp_tsdoc() {", image: "registry.example/builder:1",
                    skip: "No TypeScript sources under src/: no docs" },
    "love" => { call: "warp_ldoc", helper: "warp_ldoc() {", image: "registry.example/ci-tools:1", skip: "No Lua sources: no docs" },
    "bevy" => { call: "warp_rustdoc", helper: "warp_rustdoc() {", image: "registry.example/builder:1", skip: "No Cargo.toml: no docs" }
  }

  [ WarpEngine::CI::Woodpecker::PipelineConfig, WarpEngine::CI::Gitlab::PipelineConfig ].product(cases.keys).each do |config_class, platform|
    expected = cases.fetch(platform)

    describe "#{config_class} #{platform}" do
      define_method(:render) do |options = {}|
        config_class.new(platforms: { platform => { builder: "registry.example/builder:1", tools: "registry.example/ci-tools:1" } })
                    .render(platform: platform, name: "game", update_server: "https://games.example", options: options)
      end

      it "writes the docs with its helper in the right image" do
        yaml = render
        script = step_script(yaml, "docs")

        expect(script).to include(expected[:helper], "NAME='game'")
        expect(script.lines.last.strip).to eq(expected[:call])
        expect(yaml).to include(expected[:image])
      end

      it "writes no docs and does not fail without sources" do
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, ".version"), "1.0")
          script = step_script(render, "docs").lines.reject { |line| line.start_with?("npm ci") }.join
          output, status = Open3.capture2e("sh", "-c", script, chdir: dir)

          expect(status).to be_success
          expect(output).to include(expected[:skip])
        end
      end

      it "builds no docs when the marker disables them" do
        expect(render({ "disable" => "docs" })).not_to include(expected[:call])
      end
    end
  end

  it "uploads the electron docs when the build made them" do
    yaml = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "electron" => { builder: "b" } })
                                                     .render(platform: "electron", name: "game", update_server: "https://games.example")
    files = { "game-1.0-linux-x64.zip" => "z", "game-1.0-docs.zip" => "z", "metadata.json" => "{}" }
    calls, status = run_with_fake_curl(step_script(yaml, "upload"), files: files)

    expect(status).to be_success
    expect(uploaded_files(calls)).to include("game-1.0-docs.zip", "game-1.0-linux-x64.zip")
  end

  %w[love bevy].each do |platform|
    it "uploads the #{platform} docs when the build made them" do
      yaml = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { platform => { builder: "b" } })
                                                       .render(platform: platform, name: "game", update_server: "https://games.example")
      files = { "game-1.0.html.zip" => "z", "game-1.0-docs.zip" => "z", "metadata.json" => "{}" }
      calls, status = run_with_fake_curl(step_script(yaml, "upload"), files: files)

      expect(status).to be_success
      expect(uploaded_files(calls)).to include("game-1.0-docs.zip", "game-1.0.html.zip")
    end
  end

  it "installs LDoc for the love docs where there is no tools image" do
    yaml = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "love" => { builder: "b" } })
                                                     .render(platform: "love", name: "game", update_server: "https://games.example")

    expect(step_script(yaml, "docs")).to include("W_SETUP='apk add", "luarocks install ldoc")
  end

  it "uploads the dos docs beside the program folder" do
    skip "the upload's prepare lines need jq" unless system("command -v jq >/dev/null 2>&1")
    yaml = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "dos" => { builder: "b" } })
                                                     .render(platform: "dos", name: "game", update_server: "https://games.example")
    files = { "metadata.json" => %({"name": "game", "dos": {"folder": "GAME"}}), "dist/GAME-v1.0.zip" => "dos", "game-1.0-docs.zip" => "z" }
    calls, status = run_with_fake_curl(step_script(yaml, "upload"), files: files, version: "1.0", env: { "CI_COMMIT_TAG" => "v1.0" })

    expect(status).to be_success
    expect(uploaded_files(calls)).to include("game-1.0.zip", "game-1.0-docs.zip")
  end
end
