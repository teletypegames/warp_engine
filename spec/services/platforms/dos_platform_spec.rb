require "rails_helper"

RSpec.describe "the dos platform" do
  let(:platform) { WarpEngine::Platform.find!("dos") }

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

    release = platform.publish("dosinst", "0.6.0").reload

    expect(release.software).to have_attributes(platform: "dos", title: "DOSINST", category: "tool")
    expect(release.release_assets.map { |asset| [ asset.kind, File.basename(asset.path) ] })
      .to contain_exactly([ "cartridge", "dosinst-0.6.0.zip" ], [ "win_x86", "dosinst-0.6.0-win-x86.zip" ])
  end

  it "publishes a DOS-only program with the cartridge alone" do
    release = platform.publish("dosinst", "0.6.0").reload

    expect(release.release_assets.map(&:kind)).to eq([ "cartridge" ])
  end

  it "is download only" do
    release = platform.publish("dosinst", "0.6.0").reload
    release.release_assets.build(kind: "html", path: File.join(tmpdir, "dosinst-0.6.0"))

    expect(release).not_to be_valid
    expect(release.errors[:base].join).to include("DOS releases cannot be web playable")
  end

  describe "its shelf folder" do
    let(:dos) do
      { "folder" => "DOSINST", "settings" => [ "DOSINST.CFG" ], "store_name" => "DOSInst Store", "store_description" => "Installs.",
        "win32_folder" => "DOSINSTW", "win32_store_name" => "DOSInst for Windows" }
    end

    it "reads the DOS folder and the Win32 folder from the dos block, with the settings of both" do
      expect(WarpEngine::Platform::DosShelfFolder.call({ "dos" => dos }, "cartridge"))
        .to eq(folder: "DOSINST", settings: [ "DOSINST.CFG" ], name: "DOSInst Store", description: "Installs.", platform: "DOS")
      expect(WarpEngine::Platform::DosShelfFolder.call({ "dos" => dos }, "win_x86"))
        .to eq(folder: "DOSINSTW", settings: [ "DOSINST.CFG" ], name: "DOSInst for Windows", description: "", platform: "WIN32")
    end

    it "has nothing for a release without a dos block, a kind it does not build or a missing Win32 folder" do
      expect(WarpEngine::Platform::DosShelfFolder.call({}, "cartridge")).to be_nil
      expect(WarpEngine::Platform::DosShelfFolder.call({ "dos" => dos }, "html")).to be_nil
      expect(WarpEngine::Platform::DosShelfFolder.call({ "dos" => dos.except("win32_folder") }, "win_x86")).to be_nil
    end

    it "releases from tags" do
      expect(platform.release_rule).to eq("tag")
      expect(WarpEngine::Platform.find!("c64").release_rule).to be_nil
    end
  end
end
