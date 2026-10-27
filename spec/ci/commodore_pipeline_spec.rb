require "rails_helper"

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
        yaml = render(config_class)

        expect(yaml).to include('FILES="warp64u-$VERSION.prg warp64u-$VERSION.metadata.json"',
                                'if [ -f "$f" ]; then FILES="$FILES $f"; fi')
      end
    end
  end
end
