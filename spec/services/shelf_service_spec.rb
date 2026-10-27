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

RSpec.describe WarpEngine::ShelfService, "on a folders shelf" do
  let(:container) { Dir.mktmpdir }
  let(:shelf_dir) { File.join(container, "shelves/APPS") }
  let(:definition) { { platform: "dos", kind: %w[cartridge win_x86], layout: "folders", path: "shelves/APPS" } }
  let(:shelf) { WarpEngine::Shelves.all.first }
  let(:dos_block) do
    { folder: "DOSINST", files: %w[DOSINST.EXE DOSINST.CFG README.md], settings: %w[DOSINST.CFG],
      store_name: "DOSInst Store", store_description: "Installs DOS programs.",
      win32_folder: "DOSINSTW", win32_store_name: "DOSInst for Windows" }
  end

  before do
    allow(WarpEngine.config).to receive_messages(file_container_path: container, shelves: [ definition ])
    allow(WarpEngine::Shelves).to receive(:refresh)
    WarpEngine::SoftwareStatus.seed_defaults!
  end

  after { FileUtils.rm_rf(container) }

  def zip(path, folder, files)
    Zip::File.open(path, create: true) do |archive|
      files.each { |name, content| archive.get_output_stream("#{folder}/#{name}") { |io| io.write(content) } }
    end
  end

  def publish(version, dos: dos_block, exe: "MZ#{version}", win32: true, name: "dosinst")
    software = WarpEngine::Software.find_by(name: name) ||
               create(:software, name: name, title: name.upcase, platform: "dos", status: "released")
    release = create(:release, software: software, version: version)
    cartridge = File.join(container, "#{name}-#{version}.zip")
    zip(cartridge, "DOSINST", "DOSINST.EXE" => exe, "DOSINST.CFG" => "PATH=/APPS\r\n", "README.md" => "readme",
                              "DATA/LEVEL1.DAT" => "level")
    WarpEngine::ReleaseAsset.create!(release: release, kind: "cartridge", path: cartridge)
    if win32
      windows = File.join(container, "#{name}-#{version}-win-x86.zip")
      zip(windows, "DOSINSTW", "DOSINSTW.EXE" => "PE#{version}", "DOSINST.CFG" => "PATH=/APPS\r\n")
      WarpEngine::ReleaseAsset.create!(release: release, kind: "win_x86", path: windows)
    end
    metadata = { name: name, title: name.upcase, version: version }
    metadata[:dos] = dos if dos
    File.write(File.join(container, "#{name}-#{version}.metadata.json"), metadata.to_json)
    software
  end

  def sync = described_class.new(shelf).sync!

  def read(*path) = File.binread(File.join(shelf_dir, *path))

  it "puts a folder of each kind on the shelf, without the settings, with an INFO.INI and a FILES.LST" do
    publish("0.6.0")
    publish("0.6.1")

    sync

    expect(Dir.children(shelf_dir)).to contain_exactly("INDEX.TXT", "DOSINST", "DOSINSTW")
    expect(Dir.glob("**/*", base: File.join(shelf_dir, "DOSINST")).sort)
      .to eq(%w[DATA DATA/LEVEL1.DAT DOSINST.EXE FILES.LST INFO.INI README.md])
    expect(read("DOSINST", "DOSINST.EXE")).to eq("MZ0.6.1")
    expect(read("DOSINST", "INFO.INI"))
      .to eq("[program]\r\nname=DOSInst Store\r\ndescription=Installs DOS programs.\r\nversion=0.6.1\r\nplatform=DOS\r\n")
    expect(read("DOSINSTW", "INFO.INI")).to include("name=DOSInst for Windows\r\n", "platform=WIN32\r\n")
    expect(read("DOSINSTW", "INFO.INI")).not_to include("DOSInst Store")
  end

  it "lists every file but itself in FILES.LST, as DOSINST checks them" do
    publish("0.6.1")

    sync

    lines = read("DOSINST", "FILES.LST").split("\r\n")
    expect(lines.map { |line| line.split(" ", 3).last }).to eq(%w[DATA/LEVEL1.DAT DOSINST.EXE INFO.INI README.md])
    expect(lines[1]).to eq("#{format('%08x', Zlib.crc32('MZ0.6.1'))} 7 DOSINST.EXE")
  end

  it "keeps a folder it did not write, and removes one that left the catalog" do
    FileUtils.mkdir_p(File.join(shelf_dir, "HELLO"))
    software = publish("0.6.1")
    sync

    software.soft_delete!
    result = sync

    expect(result.removed).to contain_exactly("DOSINST", "DOSINSTW")
    expect(Dir.children(shelf_dir)).to contain_exactly("INDEX.TXT", "HELLO")
  end

  it "rewrites a folder only for a new release, and replaces it whole" do
    publish("0.6.0")
    sync
    File.write(File.join(shelf_dir, "DOSINST", "STALE.TXT"), "left over")

    expect(sync).not_to be_changed

    publish("0.6.1")
    result = sync

    expect(result.written.map(&:file)).to contain_exactly("DOSINST", "DOSINSTW")
    expect(File.exist?(File.join(shelf_dir, "DOSINST", "STALE.TXT"))).to be(false)
    expect(Dir.children(shelf_dir)).not_to include("DOSINST.NEW", "DOSINST.OLD")
  end

  it "leaves a program without a Win32 build with its DOS folder only, and skips one without a dos block" do
    publish("0.6.1", win32: false)
    publish("1.0.0", dos: nil, name: "nometa")

    entries, skipped = described_class.new(shelf).plan

    expect(entries.map(&:file)).to eq([ "DOSINST" ])
    expect(skipped.map(&:to_s)).to eq([ "nometa: no cartridge folder in the metadata of 1.0.0; no win_x86 folder in the metadata of 1.0.0" ])
  end

  it "skips a folder name a DOS store cannot hold" do
    publish("0.6.1", dos: dos_block.merge(folder: "DOSINSTALLER"), win32: false)

    expect(described_class.new(shelf).plan.last.map(&:to_s))
      .to eq([ "dosinst: \"DOSINSTALLER\" is not a usable folder name; no win_x86 asset in any release" ])
  end

  it "refuses a zip entry that climbs out of the folder" do
    software = publish("0.6.1", win32: false)
    zip(File.join(container, "dosinst-0.6.1.zip"), "DOSINST", "../EVIL.EXE" => "x")
    software.reload

    expect { sync }.to raise_error(ArgumentError, /unsafe path/)
    expect(File.exist?(File.join(container, "shelves", "EVIL.EXE"))).to be(false)
  end
end
