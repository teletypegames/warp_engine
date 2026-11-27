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

  it "publishes a program with the package alone, without a browser player" do
    release = platform.publish("we-c64", "0.1.1").reload

    expect(release.release_assets.map(&:kind)).to eq([ "package" ])
  end

  it "publishes a disk image as the package when the build made one instead of a program" do
    File.delete(File.join(dir, "we-c64-0.1.1.prg"))
    File.binwrite(File.join(dir, "we-c64-0.1.1.d64"), "disk")

    release = platform.publish("we-c64", "0.1.1").reload

    expect(release.release_assets.map { |asset| [ asset.kind, File.basename(asset.path.to_s) ] })
      .to eq([ [ "package", "we-c64-0.1.1.d64" ] ])
  end

  it "prefers the program when the build made a program and a disk image" do
    File.binwrite(File.join(dir, "we-c64-0.1.1.d64"), "disk")

    release = platform.publish("we-c64", "0.1.1").reload

    expect(release.release_assets.map { |asset| File.basename(asset.path.to_s) }).to eq([ "we-c64-0.1.1.prg" ])
  end

  it "refuses a release without the program, its required kind, and records nothing" do
    File.delete(File.join(dir, "we-c64-0.1.1.prg"))

    expect { platform.publish("we-c64", "0.1.1") }
      .to raise_error(WarpEngine::Platforms::MissingAssetsError, /package/)
    expect(WarpEngine::Software.find_by(name: "we-c64")).to be_nil
  end

  it "leaves a browser player upload alone: the release plays in the EmulatorJS runtime" do
    Zip::File.open(File.join(dir, "we-c64-0.1.1.html.zip"), create: true) do |zip|
      zip.get_output_stream("index.html") { |io| io.write("<html></html>") }
    end

    release = platform.publish("we-c64", "0.1.1").reload

    expect(release.release_assets.map(&:kind)).to eq([ "package" ])
    expect(File.exist?(File.join(dir, "html"))).to be(false)
  end
end
