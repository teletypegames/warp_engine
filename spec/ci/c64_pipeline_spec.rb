require "rails_helper"

RSpec.describe "c64 pipeline" do
  [ WarpEngine::CI::Woodpecker::PipelineConfig, WarpEngine::CI::Gitlab::PipelineConfig ].each do |config_class|
    describe config_class do
      def render(config_class, options = {})
        config_class.new(platforms: { "c64" => { builder: "registry.example/c64-builder:1", exporter: "registry.example/commodore-player:1" } })
                    .render(platform: "c64", name: "warp64u", update_server: "https://games.example", options: options)
      end

      it "assembles main.asm with ACME by default" do
        yaml = render(config_class)

        expect(yaml).to include("acme -f cbm -o warp64u.prg main.asm")
        expect(yaml).not_to include("make warp64u.prg")
        expect { YAML.safe_load(yaml) }.not_to raise_error
      end

      it "leaves the build to the repo's Makefile when the marker says build: make" do
        yaml = render(config_class, { "build" => "make" })

        expect(yaml).to include("make warp64u.prg", "cp warp64u.prg warp64u-$VERSION.prg", "commodore-pack c64 warp64u $VERSION")
        expect(yaml).not_to include("acme")
        expect { YAML.safe_load(yaml) }.not_to raise_error
      end
    end
  end
end
