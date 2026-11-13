require "rails_helper"

RSpec.describe WarpEngine::Files do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  it "replaces a file in one rename and leaves no temporary behind" do
    target = File.join(dir, "INDEX.TXT")
    File.write(target, "old")

    described_class.atomic(target) { |temporary| File.write(temporary, "new") }

    expect(File.read(target)).to eq("new")
    expect(Dir.children(dir)).to eq(%w[INDEX.TXT])
  end

  it "keeps the old file and removes the temporary when the block fails" do
    target = File.join(dir, "INDEX.TXT")
    File.write(target, "old")

    expect { described_class.atomic(target) { |temporary| File.write(temporary, "half") && raise("boom") } }.to raise_error("boom")
    expect(File.read(target)).to eq("old")
    expect(Dir.children(dir)).to eq(%w[INDEX.TXT])
  end

  it "copies with the CRC32 of the content" do
    source = File.join(dir, "game.prg")
    File.binwrite(source, "\x01\x08hello")

    crc = described_class.copy_with_crc(source, File.join(dir, "GAME.PRG"))

    expect(crc).to eq(format("%08x", Zlib.crc32("\x01\x08hello"))).and eq(described_class.crc32(source))
  end
end
