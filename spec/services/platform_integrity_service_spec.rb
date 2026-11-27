require "rails_helper"

RSpec.describe WarpEngine::PlatformIntegrityService do
  def codes(report, platform = nil)
    (platform ? report.for(platform) : report.findings).map(&:code)
  end

  def register(name, &block)
    WarpEngine.config.register_platform(name, &block)
    registered << name
  end

  let(:registered) { [] }

  after { registered.each { |name| WarpEngine.config.platforms.delete(name) } }

  it "finds no error on the builtin platforms, every template rendered with every variant, option and the disabled kinds" do
    report = described_class.new.check(data: false)

    expect(report.errors).to be_empty, report.errors.map { |finding| "#{finding.platform}: #{finding.message}" }.join("\n")
    expect(report.platforms).to match_array(WarpEngine::Platform.names)
  end

  it "reports a name that is no platform" do
    expect(codes(described_class.new.check(names: %w[amiga], data: false))).to eq(%w[unknown])
  end

  it "reports a platform without a required kind, an upload without a name and a required kind no pipeline builds" do
    register("amiga") do
      label "Amiga"
      kind :package
      kind :html
    end
    register("atari") do
      label "Atari"
      kind :package, ext: ".atr", required: true, built: false
    end

    report = described_class.new.check(names: %w[amiga atari], data: false)

    expect(codes(report, "amiga")).to include("no_required_kind", "ext_missing")
    expect(codes(report, "atari")).to include("required_not_built")
  end

  it "reports a template that does not render" do
    register("amiga") do
      label "Amiga"
      kind :package, ext: ".adf", required: true
      ci template: "/nowhere/amiga.yaml.erb"
    end

    expect(codes(described_class.new.check(names: %w[amiga], data: false), "amiga")).to eq(%w[ci_template_missing])
  end

  it "reports a marker option the engine reads itself and one that takes no value" do
    register("amiga") do
      label "Amiga"
      kind :package, ext: ".adf", required: true
      option :disable, values: %w[web], description: "taken"
      option :media, values: [], description: "empty"
    end

    expect(codes(described_class.new.check(names: %w[amiga], data: false), "amiga")).to include("option_reserved", "option_values")
  end

  describe "the catalog's records" do
    it "reports a software on an unknown platform and the assets of kinds its platform does not publish" do
      software = create(:software, platform: "c64")
      WarpEngine::Software.where(id: create(:software).id).update_all(platform: "amiga")
      release = create(:release, software: software)
      WarpEngine::ReleaseAsset.insert_all!([ { release_id: release.id, kind: "html", path: "/data/x" } ])

      report = described_class.new.check(names: %w[c64])

      expect(codes(report, "amiga")).to eq(%w[software_platform])
      expect(report.for("c64").find { |finding| finding.code == "unexpected_assets" }.message).to include(software.name, "html")
    end

    it "reports disabled kinds the platform no longer lets the software turn off" do
      software = create(:software, platform: "c64")
      WarpEngine::Software.where(id: software.id).update_all(disabled_kinds: %w[html])

      expect(codes(described_class.new.check(names: %w[c64]), "c64")).to include("software_invalid")
    end
  end
end
