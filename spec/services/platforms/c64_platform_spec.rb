require "rails_helper"

RSpec.describe "the c64 platform" do
  let(:platform) { WarpEngine::Platform.find!("c64") }

  let(:tmpdir) { Dir.mktmpdir }
  let(:dir) { FileUtils.mkdir_p(File.join(tmpdir, "we-c64", "0.1.1")).first }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    File.write(File.join(dir, "we-c64-0.1.1.metadata.json"),
               { name: "we-c64", title: "WE64", author: "Teletype Games", category: "tool" }.to_json)
    File.binwrite(File.join(dir, "we-c64-0.1.1.prg"), "\x01\x08prg")
  end

  after { FileUtils.remove_entry(tmpdir) }

  it "publishes a program with the cartridge alone, without a browser player" do
    release = platform.publish("we-c64", "0.1.1").reload

    expect(release.release_assets.map(&:kind)).to eq([ "cartridge" ])
  end

  it "refuses a release without the program, its required kind, and records nothing" do
    File.delete(File.join(dir, "we-c64-0.1.1.prg"))

    expect { platform.publish("we-c64", "0.1.1") }
      .to raise_error(WarpEngine::Platforms::MissingAssetsError, /cartridge/)
    expect(WarpEngine::Software.find_by(name: "we-c64")).to be_nil
  end

  it "leaves a browser player upload alone: the release plays in the EmulatorJS runtime" do
    Zip::File.open(File.join(dir, "we-c64-0.1.1.html.zip"), create: true) do |zip|
      zip.get_output_stream("index.html") { |io| io.write("<html></html>") }
    end

    release = platform.publish("we-c64", "0.1.1").reload

    expect(release.release_assets.map(&:kind)).to eq([ "cartridge" ])
    expect(File.exist?(File.join(dir, "html"))).to be(false)
  end
end
