require "rails_helper"

RSpec.describe "the c64 platform" do
  let(:platform) { WarpEngine::Platform.find!("c64") }

  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    File.write(File.join(tmpdir, "warp64u-0.1.1.metadata.json"),
               { name: "warp64u", title: "WARP64U", author: "Teletype Games", category: "tool" }.to_json)
    File.binwrite(File.join(tmpdir, "warp64u-0.1.1.prg"), "\x01\x08prg")
  end

  after { FileUtils.remove_entry(tmpdir) }

  it "publishes a program with the cartridge alone, without a browser player" do
    release = platform.publish("warp64u", "0.1.1").reload

    expect(release.release_assets.map(&:kind)).to eq([ "cartridge" ])
  end

  it "refuses a release without the program, its required kind, and records nothing" do
    File.delete(File.join(tmpdir, "warp64u-0.1.1.prg"))

    expect { platform.publish("warp64u", "0.1.1") }
      .to raise_error(WarpEngine::Platforms::MissingAssetsError, /cartridge/)
    expect(WarpEngine::Software.find_by(name: "warp64u")).to be_nil
  end

  it "unpacks the browser player when there is one" do
    Zip::File.open(File.join(tmpdir, "warp64u-0.1.1.html.zip"), create: true) do |zip|
      zip.get_output_stream("index.html") { |io| io.write("<html></html>") }
    end

    release = platform.publish("warp64u", "0.1.1").reload

    expect(release.release_assets.map(&:kind)).to contain_exactly("cartridge", "html")
    expect(File.read(File.join(tmpdir, "warp64u-0.1.1", "index.html"))).to eq("<html></html>")
  end
end
