require "rails_helper"

shared_examples "pipeline config built kinds" do |config_class|
  built_kinds = config_class::BUILT_KINDS

  def self.fragment_for(kind)
    case kind
    when "html" then ".html.zip"
    when "docs" then "-docs.zip"
    when "cartridge", "source" then nil
    else kind.tr("_", "-")
    end
  end

  define_method(:config_for) do |platform|
    config_class.new(platforms: { platform => { builder: "builder:latest", exporter: "exporter:latest" } })
  end

  it "knows every platform in the registry" do
    expect(built_kinds.keys).to match_array(WarpEngine::Platform.names)
  end

  WarpEngine::Platform::NAMES.each do |platform|
    context platform do
      let(:kinds) { built_kinds.fetch(platform) }
      let(:rendered) do
        config_for(platform).render(platform: platform, name: "example", update_server: "https://example.test")
      end

      it "claims only kinds the updater knows how to ingest" do
        expect(kinds - WarpEngine::Platform.find(platform).expected_kinds).to be_empty
      end

      it "claims only kinds the pipeline actually packages" do
        kinds.each do |kind|
          fragment = self.class.fragment_for(kind)
          next if fragment.nil?

          expect(rendered).to include(fragment), "#{platform}: nothing in the pipeline produces #{kind}"
        end
      end
    end
  end

  describe "#built_kinds" do
    it "answers with the kinds of a platform it has a builder for" do
      expect(config_for("tic80").built_kinds("tic80")).to include("cartridge", "html", "win_x64")
    end

    it "answers nil for a platform with no builder configured, so nothing is excused" do
      expect(config_for("tic80").built_kinds("godot")).to be_nil
    end
  end
end

RSpec.describe WarpEngine::CI::Woodpecker::PipelineConfig do
  include_examples "pipeline config built kinds", described_class
end

RSpec.describe WarpEngine::CI::Gitlab::PipelineConfig do
  include_examples "pipeline config built kinds", described_class
end
