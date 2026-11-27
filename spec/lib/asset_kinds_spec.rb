require "rails_helper"

RSpec.describe WarpEngine::AssetKinds do
  it "reads the old kind name cartridge as package" do
    expect(described_class.canonical("cartridge")).to eq("package")
    expect(described_class.canonical(:cartridge)).to eq("package")
    expect(described_class.fetch("cartridge").name).to eq("package")
    expect(described_class.canonical_list(%w[cartridge package win_x64])).to eq(%w[package win_x64])
  end

  it "only ever lists the new name" do
    expect(described_class.names).to include("package")
    expect(described_class.names).not_to include("cartridge")
  end

  it "stores an asset sent with the old kind name under the new one" do
    release = create(:release, software: create(:software, platform: "c64"), version: "1.0.0")

    asset = WarpEngine::ReleaseAsset.create!(release: release, kind: "cartridge", path: "/softwares/x.prg")

    expect(asset.reload.kind).to eq("package")
  end

  it "turns off a kind named the old way" do
    software = WarpEngine::Software.new(platform: "tic80", disabled_kinds: "web, cartridge")

    expect(software.disabled_kinds).to eq(%w[web package])
  end
end
