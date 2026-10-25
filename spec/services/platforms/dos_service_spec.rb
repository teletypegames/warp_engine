require "rails_helper"

RSpec.describe WarpEngine::Platforms::Dos::Service do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    File.write(File.join(tmpdir, "dosinst-0.6.0.metadata.json"),
               { name: "dosinst", title: "DOSINST", author: "Teletype Games", category: "tool" }.to_json)
    File.binwrite(File.join(tmpdir, "dosinst-0.6.0.zip"), "PK dos")
  end

  after { FileUtils.remove_entry(tmpdir) }

  it "takes the program folder as the cartridge and the Win32 folder as win_x86" do
    File.binwrite(File.join(tmpdir, "dosinst-0.6.0-win-x86.zip"), "PK win32")

    release = described_class.new.update("dosinst", "0.6.0").reload

    expect(release.software).to have_attributes(platform: "dos", title: "DOSINST", category: "tool")
    expect(release.release_assets.map { |asset| [ asset.kind, File.basename(asset.path) ] })
      .to contain_exactly([ "cartridge", "dosinst-0.6.0.zip" ], [ "win_x86", "dosinst-0.6.0-win-x86.zip" ])
  end

  it "publishes a DOS-only program with the cartridge alone" do
    release = described_class.new.update("dosinst", "0.6.0").reload

    expect(release.release_assets.map(&:kind)).to eq([ "cartridge" ])
  end

  it "is download only" do
    release = described_class.new.update("dosinst", "0.6.0").reload
    release.release_assets.build(kind: "html", path: File.join(tmpdir, "dosinst-0.6.0"))

    expect(release).not_to be_valid
    expect(release.errors[:base].join).to include("DOS releases cannot be web playable")
  end
end
