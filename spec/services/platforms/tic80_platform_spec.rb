require "rails_helper"
require "zip"

RSpec.describe "the tic80 platform" do
  let(:platform) { WarpEngine::Platform.find!("tic80") }

  let(:tmpdir) { Dir.mktmpdir }
  let(:name) { "spectic" }
  let(:version) { "9.9" }
  let(:versioned) { "#{name}-#{version}" }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)

    write_zip("#{versioned}.html.zip", "index.html" => "<html></html>")
    File.write(File.join(tmpdir, "#{versioned}.tic"), "TIC!")
    File.write(File.join(tmpdir, "#{versioned}.lua"), <<~LUA)
      -- title: Spec TIC
      -- name: #{name}
      -- author: RSpec
      -- desc: spec fixture
      -- version: #{version}
      function TIC() end
    LUA
  end

  after do
    FileUtils.remove_entry(tmpdir)
    WarpEngine::Software.unscoped.where(name: name).each do |sw|
      WarpEngine::Release.unscoped.where(software_id: sw.id).each do |r|
        WarpEngine::ReleaseAsset.unscoped.where(release_id: r.id).delete_all
        r.delete
      end
      WarpEngine::ExternalLink.unscoped.where(software_id: sw.id).delete_all
      sw.delete
    end
  end

  def write_zip(filename, entries)
    Zip::File.open(File.join(tmpdir, filename), create: true) do |zip|
      entries.each do |entry_name, content|
        zip.get_output_stream(entry_name) { |io| io.write(content) }
      end
    end
  end

  def asset_kinds(release)
    WarpEngine::ReleaseAsset.unscoped.where(release_id: release.id).pluck(:kind)
  end

  it "registers the release without a docs zip" do
    release = platform.publish(name, version)

    expect(asset_kinds(release)).to match_array(%w[cartridge source html])
  end

  it "reads the category from the cartridge header, and leaves it empty when there is none" do
    release = platform.publish(name, version)
    expect(WarpEngine::Software.find(release.software_id).category).to be_nil

    File.write(File.join(tmpdir, "#{versioned}.lua"), <<~LUA)
      -- title: Spec TIC
      -- name: #{name}
      -- category: puzzle
      function TIC() end
    LUA

    release = platform.publish(name, version)
    expect(WarpEngine::Software.find(release.software_id).category).to eq("puzzle")
  end

  it "registers docs when the docs zip is present" do
    write_zip("#{versioned}-docs.zip", "index.html" => "docs")

    release = platform.publish(name, version)

    expect(asset_kinds(release)).to include("docs")
  end

  it "registers binary assets when slug zips are present" do
    write_zip("#{versioned}-win-x64.zip", "game.exe" => "MZ")
    write_zip("#{versioned}-mac-x64.zip", "game" => "bin")

    release = platform.publish(name, version)

    expect(asset_kinds(release)).to include("win_x64", "mac_x64")
    expect(asset_kinds(release)).not_to include("linux_x64")
  end

  it "discards assets of kinds the platform no longer expects and keeps the expected ones" do
    software = WarpEngine::Software.create!(name: name, platform: "tic80", title: "Spec TIC")
    release = WarpEngine::Release.create!(software_id: software.id, version: version)
    WarpEngine::ReleaseAsset.create!(release: release, kind: "mac_universal", path: "/s/#{versioned}-mac-universal.zip")
    WarpEngine::ReleaseAsset.create!(release: release, kind: "mac_x64", path: "/s/#{versioned}-mac-x64.zip")

    platform.publish(name, version)

    kept = WarpEngine::ReleaseAsset.kept.where(release_id: release.id).pluck(:kind)
    expect(kept).to match_array(%w[cartridge source html mac_x64])
    expect(WarpEngine::ReleaseAsset.discarded.where(release_id: release.id).pluck(:kind)).to eq(%w[mac_universal])
  end

  it "exposes expected_kinds from included Build concerns" do
    expect(platform.expected_kinds).to match_array(
      %w[cartridge source html docs win_x64 linux_x64 mac_x64]
    )
  end
end
