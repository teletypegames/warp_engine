require "rails_helper"
require_relative "../support/pipeline_helpers"

RSpec.describe "Commodore pipelines" do
  [ WarpEngine::CI::Woodpecker::PipelineConfig, WarpEngine::CI::Gitlab::PipelineConfig ].product(%w[c64 plus4]).each do |config_class, platform|
    describe "#{config_class} #{platform}" do
      define_method(:render) do |config_class, options = {}|
        config_class.new(platforms: { platform => { builder: "registry.example/builder:1", exporter: "registry.example/commodore-player:1" } })
                    .render(platform: platform, name: "we-c64", update_server: "https://games.example", options: options)
      end

      it "assembles main.asm with ACME by default" do
        yaml = render(config_class)

        expect(yaml).to include("acme -f cbm -o we-c64.prg main.asm")
        expect(yaml).not_to include("make we-c64.prg")
        expect { YAML.safe_load(yaml) }.not_to raise_error
      end

      it "leaves the build to the repo's Makefile when the marker says build: make" do
        yaml = render(config_class, { "build" => "make" })

        expect(yaml).to include("make we-c64.prg", "cp we-c64.prg we-c64-$VERSION.prg", "commodore-pack #{platform} we-c64 $VERSION")
        expect(yaml).not_to include("acme")
        expect { YAML.safe_load(yaml) }.not_to raise_error
      end

      it "builds a disk image with the repo's Makefile when the marker says media: d64" do
        yaml = render(config_class, { "media" => "d64" })

        expect(yaml).to include("make we-c64.d64", "cp we-c64.d64 we-c64-$VERSION.d64")
        expect(yaml).not_to include("acme", "make we-c64.prg")
        expect { YAML.safe_load(yaml) }.not_to raise_error
      end

      it "generates versioned Doxygen docs from the C sources under src/" do
        yaml = render(config_class, { "build" => "make" })

        expect(yaml).to include("doxygen -", "PROJECT_NUMBER", "we-c64-$VERSION-docs.zip")
        expect { YAML.safe_load(yaml) }.not_to raise_error
      end

      it "skips the docs of a repository without C sources" do
        script = step_script(render(config_class), "docs")

        Dir.mktmpdir do |dir|
          output, status = Open3.capture2e("sh", "-c", script, chdir: dir)
          expect(status).to be_success
          expect(output).to include("No C sources under src/")
        end
      end

      it "uploads the docs when the build made them" do
        script = step_script(render(config_class, { "build" => "make" }), "upload")

        calls, status = run_with_fake_curl(script, files: { "we-c64-1.0.prg" => "prg", "we-c64-1.0-docs.zip" => "z", "metadata.json" => "{}" })
        expect(status).to be_success
        expect(uploaded_files(calls)).to contain_exactly("we-c64-1.0.prg", "we-c64-1.0-docs.zip", "we-c64-1.0.metadata.json")
      end

      it "leaves out the players and keeps the docs when the marker disables them, and tells the publish" do
        yaml = render(config_class, { "build" => "make", "disable" => "web win_x64 linux_x64 mac_arm64" })

        expect(yaml).not_to include("commodore-pack")
        expect(yaml).to include("doxygen -")
        expect(step_script(yaml, "publish")).to include("DISABLE='web,win_x64,linux_x64,mac_arm64'")
        calls, = run_with_fake_curl(step_script(yaml, "upload"),
                                    files: { "we-c64-1.0.prg" => "p", "we-c64-1.0-docs.zip" => "z", "we-c64-1.0-win-x64.zip" => "z", "metadata.json" => "{}" })
        expect(uploaded_files(calls)).to contain_exactly("we-c64-1.0.prg", "we-c64-1.0-docs.zip", "we-c64-1.0.metadata.json")
      end

      it "takes the disabled kinds as a YAML list too, and builds no docs when they are disabled" do
        yaml = render(config_class, { "build" => "make", "disable" => %w[docs mac_arm64] })

        expect(yaml).not_to include("doxygen -")
        expect(yaml).to include("commodore-pack")
        expect(step_script(yaml, "publish")).to include("DISABLE='docs,mac_arm64'")
      end

      it "sends no disabled kinds without the marker key" do
        expect(step_script(render(config_class), "publish")).not_to include("DISABLE=")
      end

      it "uploads a disk image in place of the program when the build made one" do
        script = step_script(render(config_class, { "media" => "d64" }), "upload")

        calls, status = run_with_fake_curl(script, files: { "we-c64-1.0.d64" => "disk", "metadata.json" => "{}" })
        expect(status).to be_success
        expect(uploaded_files(calls)).to contain_exactly("we-c64-1.0.d64", "we-c64-1.0.metadata.json")
      end

      it "uploads the program and its metadata always, and the players only when they were built" do
        script = step_script(render(config_class), "upload")
        program = { "we-c64-1.0.prg" => "prg", "metadata.json" => "{}" }

        calls, status = run_with_fake_curl(script, files: program, env: { "UPDATE_SERVER" => "https://games.example" })
        expect(status).to be_success
        expect(uploaded_files(calls)).to contain_exactly("we-c64-1.0.prg", "we-c64-1.0.metadata.json")
        expect(calls.first).to include("https://games.example/build/upload?name=we-c64&version=1.0")

        calls, = run_with_fake_curl(script, files: program.merge("we-c64-1.0.html.zip" => "z", "we-c64-1.0-win-x64.zip" => "z"))
        expect(uploaded_files(calls)).to contain_exactly("we-c64-1.0.prg", "we-c64-1.0.metadata.json",
                                                         "we-c64-1.0-win-x64.zip")
      end

      it "fails the upload without the program, the kind the platform requires" do
        _, status = run_with_fake_curl(step_script(render(config_class), "upload"), files: { "metadata.json" => "{}" })

        expect(status).not_to be_success
      end

      it "publishes the build under its own platform" do
        calls, = run_with_fake_curl(step_script(render(config_class), "publish"),
                                    env: { "UPDATE_SERVER" => "https://u.example", "CI_COMMIT_SHA" => "abc1234" })

        expect(calls.last).to end_with("https://u.example/build/publish?name=we-c64&platform=#{platform}&version=1.0&commit=abc1234")
      end
    end
  end
end
