require "rails_helper"
require_relative "../support/sync_helpers"

RSpec.describe WarpEngine::Sync::Filter do
  include SyncHelpers

  let(:software) { build(:software, name: "blessingofra", platform: "c64", status: "released", category: "game") }
  let(:release) { build(:release, software: software, version: "1.2.0") }

  def reason(**settings) = described_class.new(sync_config(**settings)).reason(release)

  it "lets a stable release go with the defaults" do
    expect(reason).to be_nil
  end

  it "holds back beta and dev releases unless their channel is allowed" do
    release.version = "1.3.0-beta.1"
    expect(reason).to include("beta channel")
    expect(reason(allowed_channels: %w[stable beta])).to be_nil

    release.version = "dev-1.3.0-feature"
    expect(reason(allowed_channels: %w[stable beta])).to include("dev channel")
  end

  it "follows the per-software switch" do
    expect(reason(software_switch: :opt_in)).to include("not switched on")
    software.sync_enabled = true
    expect(reason(software_switch: :opt_in)).to be_nil
    software.sync_enabled = false
    expect(reason(software_switch: :opt_out)).to include("switched off")
    software.sync_enabled = nil
    expect(reason(software_switch: :opt_out)).to be_nil
    expect(reason(software_switch: false)).to be_nil
  end

  it "denies by name with wildcards, category, platform and status" do
    expect(reason(denied_softwares: %w[blessing*])).to include("denied_softwares")
    expect(reason(denied_softwares: %w[BLESSINGOFRA])).to include("denied_softwares")
    expect(reason(denied_softwares: %w[bless])).to be_nil
    expect(reason(denied_categories: %w[game])).to include("denied_categories")
    expect(reason(denied_platforms: %w[c64])).to include("denied_platforms")
    expect(reason(denied_statuses: %w[released])).to include("denied_statuses")
  end

  it "lets a denied list win over the switch and the allowed lists" do
    software.sync_enabled = true
    expect(reason(software_switch: :opt_in, allowed_softwares: %w[blessingofra], denied_platforms: %w[c64])).to include("denied_platforms")
  end

  it "takes the name or the category on the first axis" do
    expect(reason(allowed_categories: %w[demo])).to include("neither")
    expect(reason(allowed_categories: %w[demo], allowed_softwares: %w[blessing*])).to be_nil
    expect(reason(allowed_categories: %w[game], allowed_softwares: %w[other])).to be_nil
  end

  it "needs every axis with an allowed list to match" do
    expect(reason(allowed_categories: %w[game], allowed_platforms: %w[plus4])).to include("allowed_platforms")
    expect(reason(allowed_categories: %w[game], allowed_platforms: %w[c64], allowed_statuses: %w[development])).to include("allowed_statuses")
    expect(reason(allowed_categories: %w[game], allowed_platforms: %w[c64], allowed_statuses: %w[released])).to be_nil
  end

  it "matches no category list for a software without a category" do
    software.category = nil
    expect(reason(allowed_categories: %w[game])).to include("neither")
    expect(reason(denied_categories: %w[game])).to be_nil
  end

  it "keeps the required kinds whatever the kind lists say" do
    filter = described_class.new(sync_config(allowed_kinds: %w[html], denied_kinds: %w[cartridge]))
    kinds = filter.kind_specs(WarpEngine::Platform.find!("c64")).map(&:name)

    expect(kinds).to include("cartridge")
    expect(kinds).to include("html") if WarpEngine::Platform.find!("c64").expected_kinds.include?("html")
    expect(kinds - %w[cartridge html]).to be_empty
  end

  describe WarpEngine::Sync::Configuration do
    it "is off with stable only by default" do
      config = described_class.new

      expect(config).not_to be_enabled
      expect(config.allowed_channels).to eq(%w[stable])
      expect(config).to be_events
    end

    it "refuses unknown platforms, channels, kinds and switch values" do
      expect { sync_config(allowed_platforms: %w[amiga9]).validate! }.to raise_error(ArgumentError, /platform amiga9/)
      expect { sync_config(allowed_channels: %w[nightly]).validate! }.to raise_error(ArgumentError, /channel nightly/)
      expect { sync_config(denied_kinds: %w[floppy]).validate! }.to raise_error(ArgumentError, /asset kind floppy/)
      expect { sync_config(software_switch: :maybe).validate! }.to raise_error(ArgumentError, /software_switch/)
    end

    it "warns about a required kind a list leaves out" do
      warnings = sync_config(denied_kinds: %w[cartridge]).validate!

      expect(warnings).to include(a_string_including("c64 platform requires cartridge"))
    end
  end

  describe WarpEngine::Configuration::SyncDSL do
    it "writes the sync block into the configuration" do
      WarpEngine.configure do
        sync do
          enabled true
          software_switch :opt_out
          denied_softwares %w[*-test]
          allowed_platforms :c64, :plus4
          events :verbose
          timeout "30"
        end
      end
      config = WarpEngine.config.sync

      expect(config).to be_enabled
      expect(config.software_switch).to eq(:opt_out)
      expect(config.denied_softwares).to eq(%w[*-test])
      expect(config.allowed_platforms).to eq(%w[c64 plus4])
      expect(config).to be_verbose_events
      expect(config.timeout).to eq(30)
    end
  end
end
