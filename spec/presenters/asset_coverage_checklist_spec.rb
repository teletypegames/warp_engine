require "rails_helper"

RSpec.describe WarpEngine::AssetCoverageChecklist do
  let(:software) { create(:software, name: "rabbitroller", platform: "ebitengine") }

  before do
    release = create(:release, software: software, version: "1.1.1")
    WarpEngine::ReleaseAsset.create!(release: release, kind: "html", path: "/s/rabbitroller-1.1.1")

    ci = instance_double(WarpEngine::CI::Woodpecker::Adapter)
    allow(ci).to receive(:built_kinds) { |platform| WarpEngine::CI::Woodpecker::PipelineConfig::BUILT_KINDS[platform] }
    allow(WarpEngine).to receive(:ci).and_return(ci)
  end

  def output(**options) = described_class.new(WarpEngine::AssetCoverage.new(**options)).to_s

  it "checks off what is there and leaves the rest open" do
    lines = output.lines.map(&:chomp)

    expect(lines).to include("rabbitroller  ebitengine  v1.1.1  1/7")
    expect(lines).to include("  [x] html")
    expect(lines).to include("  [ ] linux_arm64")
    expect(lines).to include("  [-] mac_arm64")
  end

  it "lists what the CI could build and the release does not have" do
    expect(output).to include("The CI can build these and the release does not have them:")
    expect(output).to include("rabbitroller v1.1.1 (ebitengine): win_x86, win_x64, linux_x64, linux_arm64")
  end

  it "counts the assets and says how many the CI does not build" do
    expect(output).to include("1 softwares, 1 releases, 1/7 assets present, 4 missing from CI-built kinds")
    expect(output).to include("2 assets are expected but this CI does not build them")
  end

  it "shows only the incomplete releases when asked" do
    complete = create(:software, name: "pong", platform: "c64")
    release = create(:release, software: complete, version: "0.1")
    %w[cartridge html win_x64 linux_x64 mac_arm64].each do |kind|
      WarpEngine::ReleaseAsset.create!(release: release, kind: kind, path: "/s/pong-0.1-#{kind}")
    end

    text = described_class.new(WarpEngine::AssetCoverage.new, only_missing: true).to_s

    expect(text).to include("rabbitroller")
    expect(text).not_to include("pong")
  end

  it "says so when there is nothing to report" do
    text = described_class.new(WarpEngine::AssetCoverage.new(name: "nothing-here")).to_s

    expect(text).to include("Nothing to report.")
  end
end
