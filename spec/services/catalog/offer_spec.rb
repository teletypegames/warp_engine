require "rails_helper"
require "tmpdir"

RSpec.describe WarpEngine::Catalog::Offer do
  let(:container) { Dir.mktmpdir }
  let(:offer) { described_class.new(platforms: %w[c64], kinds: %w[cartridge]) }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(container)
    allow(WarpEngine::Outlets).to receive(:refresh)
    WarpEngine::SoftwareStatus.seed_defaults!
  end

  after do
    FileUtils.rm_rf(container)
    WarpEngine::AccessPolicy.reset!
  end

  def publish(name, version, platform: "c64", status: "released", kind: "cartridge", write: true)
    software = WarpEngine::Software.find_by(name: name) ||
               create(:software, name: name, title: name.titleize, platform: platform, status: status)
    path = File.join(container, "#{name}-#{version}.prg")
    File.binwrite(path, "#{name}-#{version}") if write
    release = create(:release, software: software, version: version)
    WarpEngine::ReleaseAsset.create!(release: release, kind: kind, path: path)
    software
  end

  it "offers the latest release with the kind of every listed title of the platforms" do
    ariadne = publish("ariadne", "1.0.0")
    publish("ariadne", "1.1.0")
    publish("tetris", "1.0.0", platform: "tic80")

    items, skips = offer.plan

    expect(items.map { |item| [ item.software, item.release.version, item.kind ] }).to eq([ [ ariadne, "1.1.0", "cartridge" ] ])
    expect(items.first.size).to eq(13)
    expect(items.first.extension).to eq("prg")
    expect(items.first.relative_path).to eq("ariadne-1.1.0.prg")
    expect(skips).to be_empty
  end

  it "skips a title whose files are missing, and leaves out unlisted statuses" do
    publish("ghost", "1.0.0", write: false)
    publish("wip", "1.0.0", status: "development")
    WarpEngine::SoftwareStatus.find_by!(key: "development").update!(default_visible: false)

    items, skips = offer.plan

    expect(items).to be_empty
    expect(skips.map(&:to_s)).to eq([ "ghost: no cartridge asset in any release" ])
  end

  it "gives one pair a kind, and a single gated pair for a gated title" do
    software = publish("ariadne", "1.0.0")
    multi = described_class.new(platforms: %w[c64], kinds: %w[cartridge html])

    expect(multi.consider(software).map(&:first)).to eq([ nil, "no html asset in any release" ])

    allow(WarpEngine.access_policy).to receive(:access_for).and_return(WarpEngine::Access.new(gated: true, entitled: false))
    expect(multi.consider(software)).to eq([ [ "gated", nil ] ])
  end

  it "finds the items of one title by id" do
    software = publish("ariadne", "1.0.0")

    expect(offer.items_of(software.id).map(&:software)).to eq([ software ])
    expect(offer.items_of(0)).to eq([])
  end

  it "reads the metadata beside the source" do
    software = publish("ariadne", "1.0.0")
    File.write(File.join(container, "ariadne-1.0.0.metadata.json"), { name: "ariadne" }.to_json)

    expect(offer.items_of(software.id).first.metadata).to eq("name" => "ariadne")
  end
end
