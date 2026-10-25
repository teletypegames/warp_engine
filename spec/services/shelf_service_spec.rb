require "rails_helper"
require "tmpdir"
require "zlib"

RSpec.describe WarpEngine::ShelfService do
  let(:container) { Dir.mktmpdir }
  let(:shelf_dir) { File.join(container, "shelves/C64") }
  let(:definition) { { platform: "c64", kind: "cartridge", path: "shelves/C64", extension: ".PRG", name_length: 16 } }
  let(:shelf) { WarpEngine::Shelves.all.first }

  before do
    allow(WarpEngine.config).to receive_messages(file_container_path: container, shelves: [ definition ])
    allow(WarpEngine::Shelves).to receive(:refresh)
    WarpEngine::SoftwareStatus.seed_defaults!
  end

  after { FileUtils.rm_rf(container) }

  def publish(name, version, content: "#{name}-#{version}", platform: "c64", status: "released", kind: "cartridge", **attributes)
    software = WarpEngine::Software.find_by(name: name) ||
               create(:software, name: name, title: name.titleize, platform: platform, status: status, **attributes)
    path = File.join(container, "#{name}-#{version}.prg")
    File.binwrite(path, content)
    release = create(:release, software: software, version: version)
    WarpEngine::ReleaseAsset.create!(release: release, kind: kind, path: path)
    software
  end

  def index_lines = File.readlines(File.join(shelf_dir, "INDEX.TXT"), chomp: true)

  def sync = described_class.new(shelf).sync!

  it "puts the latest release of every listed title on the shelf, without a version in the name" do
    publish("ariadne", "1.0.0", shelf_name: "ARIADNE")
    publish("ariadne", "1.1.0", content: "newer", shelf_name: "ARIADNE")
    publish("rabbit", "1.0.0")

    sync

    expect(Dir.children(shelf_dir)).to contain_exactly("INDEX.TXT", "ARIADNE.PRG", "RABBIT.PRG")
    expect(File.binread(File.join(shelf_dir, "ARIADNE.PRG"))).to eq("newer")
    expect(index_lines.first).to eq(described_class::HEADER)
    expect(index_lines[1]).to eq("ARIADNE.PRG|1.1.0|5|#{format('%08x', Zlib.crc32('newer'))}|Ariadne|dev|")
  end

  it "leaves out other platforms, hidden statuses, gated titles and titles without the asset" do
    publish("ariadne", "1.0.0")
    publish("plusfour", "1.0.0", platform: "plus4")
    publish("hidden", "1.0.0", status: "demo")
    publish("nocart", "1.0.0", kind: "html")
    WarpEngine::SoftwareStatus.find_by!(key: "demo").update!(default_visible: false)

    entries, skipped = described_class.new(shelf).plan

    expect(entries.map(&:file)).to eq([ "ARIADNE.PRG" ])
    expect(skipped.map(&:to_s)).to eq([ "nocart: no cartridge asset in any release" ])
  end

  it "skips a gated title" do
    publish("ariadne", "1.0.0")
    policy = WarpEngine::AccessPolicy::Open.new
    allow(policy).to receive(:access_for).and_return(WarpEngine::Access.new(gated: true))
    allow(WarpEngine).to receive(:access_policy).and_return(policy)

    entries, skipped = described_class.new(shelf).plan

    expect(entries).to be_empty
    expect(skipped.map(&:reason)).to eq([ "gated" ])
  end

  it "follows the shelf's own statuses when it names them" do
    publish("ariadne", "1.0.0", status: "development")
    definition[:statuses] = [ "released" ]

    expect(described_class.new(shelf).plan.first).to be_empty
  end

  it "derives the name from the software name when no shelf name is set, and truncates it" do
    publish("thread-of-ariadne", "1.0.0")

    expect(described_class.new(shelf).plan.first.map(&:file)).to eq([ "THREAD-OF-AR.PRG" ])
  end

  it "keeps the first title when two would share a name" do
    publish("rabbit", "1.0.0")
    publish("rabbit_", "1.0.0")

    entries, skipped = described_class.new(shelf).plan

    expect(entries.map { |entry| entry.software.name }).to eq([ "rabbit" ])
    expect(skipped.map(&:to_s)).to eq([ "rabbit_: RABBIT.PRG is taken by rabbit" ])
  end

  it "writes ASCII lines of at most 255 bytes, with the separators taken out" do
    publish("ariadne", "1.0.0", title: "Ariadné | fonala", desc: "Line one\nline two #{'x' * 400}")

    sync

    line = index_lines[1]
    expect(line.bytesize).to eq(255)
    expect(line).to start_with("ARIADNE.PRG|1.0.0|")
    expect(line).to include("|Ariadne fonala|dev|Line one line two x")
    expect(line).to be_ascii_only
  end

  it "removes what left the catalog, after the index is replaced" do
    publish("ariadne", "1.0.0")
    rabbit = publish("rabbit", "1.0.0")
    sync

    rabbit.soft_delete!
    result = sync

    expect(result.removed).to eq([ "RABBIT.PRG" ])
    expect(Dir.children(shelf_dir)).to contain_exactly("INDEX.TXT", "ARIADNE.PRG")
    expect(index_lines.size).to eq(2)
  end

  it "does nothing the second time" do
    publish("ariadne", "1.0.0")
    sync

    result = sync

    expect(result).not_to be_changed
  end

  it "copies a file again when the source is newer than the shelf copy" do
    publish("ariadne", "1.0.0", content: "aaaa")
    sync
    target = File.join(shelf_dir, "ARIADNE.PRG")
    File.utime(Time.now - 60, Time.now - 60, target)
    File.binwrite(File.join(container, "ariadne-1.0.0.prg"), "bbbb")

    result = sync

    expect(result.written.map(&:file)).to eq([ "ARIADNE.PRG" ])
    expect(File.binread(target)).to eq("bbbb")
    expect(index_lines[1]).to include(format("%08x", Zlib.crc32("bbbb")))
  end

  it "keeps the old shelf when a copy fails" do
    publish("ariadne", "1.0.0")
    sync
    before = File.read(File.join(shelf_dir, "INDEX.TXT"))
    publish("ariadne", "1.1.0")
    allow(File).to receive(:rename).and_call_original
    allow(File).to receive(:rename).with(/ARIADNE\.PRG\.NEW\z/, anything).and_raise(Errno::ENOSPC)

    expect { sync }.to raise_error(Errno::ENOSPC)
    expect(File.read(File.join(shelf_dir, "INDEX.TXT"))).to eq(before)
    expect(Dir.children(shelf_dir)).to contain_exactly("INDEX.TXT", "ARIADNE.PRG")
  end

  it "changes nothing on disk in a dry run" do
    publish("ariadne", "1.0.0")

    result = described_class.new(shelf).sync!(dry_run: true)

    expect(result.written.map(&:file)).to eq([ "ARIADNE.PRG" ])
    expect(File.exist?(shelf_dir)).to be(false)
  end

  describe "refreshing on change" do
    before { allow(WarpEngine::Shelves).to receive(:refresh).and_call_original }

    it "fills the shelf when a release is published" do
      software = create(:software, name: "ariadne", title: "Ariadne", platform: "c64", status: "released")
      FileUtils.mkdir_p(container)
      File.binwrite(File.join(container, "ariadne-1.0.0.prg"), "prg")
      Zip::File.open(File.join(container, "ariadne-1.0.0.html.zip"), Zip::File::CREATE) do |zip|
        zip.get_output_stream("index.html") { |io| io.write("<html></html>") }
      end
      File.write(File.join(container, "ariadne-1.0.0.metadata.json"),
                 { name: "ariadne", title: "Ariadne", shelf_name: "ARIADNE" }.to_json)

      WarpEngine::PublishService.new.publish(
        WarpEngine::PublishInputDto.new(platform: "c64", name: "ariadne", version: "1.0.0")
      )

      expect(software.reload.shelf_name).to eq("ARIADNE")
      expect(index_lines.last).to start_with("ARIADNE.PRG|1.0.0|3|")
    end

    it "follows a status change and a soft delete" do
      software = publish("ariadne", "1.0.0")
      expect(index_lines.size).to eq(2)

      software.update!(status: "demo")
      WarpEngine::SoftwareStatus.find_by!(key: "demo").update!(default_visible: false)
      expect(index_lines.size).to eq(1)

      software.update!(status: "released")
      expect(index_lines.size).to eq(2)

      software.releases.first.soft_delete!
      expect(index_lines.size).to eq(1)
    end

    it "does not let a failing shelf break the save" do
      allow(WarpEngine::ShelfService).to receive(:new).and_raise(Errno::EACCES)

      expect { publish("ariadne", "1.0.0") }.not_to raise_error
    end

    it "writes nothing when no shelf is configured" do
      allow(WarpEngine.config).to receive(:shelves).and_return([])

      publish("ariadne", "1.0.0")

      expect(File.exist?(shelf_dir)).to be(false)
    end
  end
end
