require "rails_helper"
require "zip"

RSpec.describe WarpEngine::Publish::Unpacker do
  let(:dir) { Dir.mktmpdir }
  let(:zip) { File.join(dir, "game-1.0.html.zip") }
  let(:target) { File.join(dir, "game-1.0") }

  after { FileUtils.remove_entry(dir) }

  def write_zip(entries)
    Zip::File.open(zip, create: true) do |archive|
      entries.each { |name, content| archive.get_output_stream(name) { |io| io.write(content) } }
    end
  end

  it "replaces the directory with the zip's content" do
    FileUtils.mkdir_p(target)
    File.write(File.join(target, "stale.js"), "old")
    write_zip("index.html" => "<html></html>", "js/game.js" => "go()")

    described_class.new.replace_dir(zip, target)

    expect(Dir.glob("**/*", base: target).sort).to eq(%w[index.html js js/game.js])
  end

  it "refuses an entry that climbs out of the directory" do
    write_zip("../escaped.txt" => "out")

    expect { described_class.new.replace_dir(zip, target) }.to raise_error(WarpEngine::Error, /unsafe path/)
    expect(File.exist?(File.join(dir, "escaped.txt"))).to be(false)
  end
end
