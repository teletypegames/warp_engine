require "rails_helper"
require_relative "../support/runtime_helpers"

RSpec.describe WarpEngine::RuntimeMaintenanceService do
  let(:tmpdir) { Dir.mktmpdir }
  let(:service) { described_class.new }
  let(:runtime_files) do
    { "loader.js" => "loader", "emulator.min.js" => "emu", "cores/vice_x64sc-wasm.data" => "vice", "cores/reports/vice_x64sc.json" => "{}" }
  end
  let(:software) { create(:software, name: "rabbit", platform: "c64") }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    stub_runtime(:emulatorjs, files: runtime_files, version: "4.2.3",
                              components: { core: [ "cores/%{key}-*wasm.data", "cores/reports/%{key}.json" ] },
                              params: { core: { required: true, component: :core }, options: { type: :hash }, joystick: { type: :hash } })
  end

  after { FileUtils.rm_rf(tmpdir) }

  def old_release(version, folder_files)
    release = create(:release, software: software, version: version)
    folder = File.join(tmpdir, "rabbit-#{version}")
    folder_files.each do |file, body|
      FileUtils.mkdir_p(File.dirname(File.join(folder, file)))
      File.binwrite(File.join(folder, file), body)
    end
    File.write("#{folder}.html.zip", "zip")
    File.binwrite(File.join(tmpdir, "rabbit-#{version}.prg"), "\x01\x08")
    release.release_assets.create!(kind: "html", path: folder)
    release.release_assets.create!(kind: "cartridge", path: File.join(tmpdir, "rabbit-#{version}.prg"))
    release
  end

  def installed
    install_runtime_version(name: "emulatorjs", version: "4.2.3", files: runtime_files, components: { "core" => %w[vice_x64sc] })
  end

  it "binds a release whose html folder holds the runtime's files bit for bit, and skips the others" do
    version = installed
    same = old_release("1.0", runtime_files.transform_keys { |file| "data/#{file}" }.merge("index.html" => "<html>"))
    other = old_release("0.9", runtime_files.merge("emulator.min.js" => "older"))

    dry = service.migrate(dry_run: true)
    expect(dry.count).to eq(1)
    expect(same.reload.runtime_version).to be_nil

    report = service.migrate(dry_run: false)
    expect(report.lines).to include("rabbit 1.0: -> emulatorjs (Emulatorjs 4.2.3)", match(/rabbit 0.9: skipped/))
    expect(same.reload).to have_attributes(runtime_version: version, web_binding: "emulatorjs")
    expect(other.reload.runtime_version).to be_nil
  end

  it "binds a folder that lacks a base file a later recipe added, but not one without the binding's core" do
    version = installed
    older = old_release("1.0", runtime_files.except("emulator.min.js"))
    coreless = old_release("0.9", runtime_files.except("cores/vice_x64sc-wasm.data"))

    service.migrate(dry_run: false)

    expect(older.reload.runtime_version).to eq(version)
    expect(coreless.reload.runtime_version).to be_nil
  end

  it "removes the html folder and zip of a release once it plays in a runtime" do
    release = old_release("1.0", runtime_files)
    release.update_columns(runtime_version_id: installed.id, web_binding: "emulatorjs")

    expect(service.prune_html(dry_run: true).count).to eq(1)
    expect(File.directory?(File.join(tmpdir, "rabbit-1.0"))).to be(true)

    service.prune_html(dry_run: false)
    expect(release.reload.release_assets.map(&:kind)).to eq([ "cartridge" ])
    expect(File.exist?(File.join(tmpdir, "rabbit-1.0"))).to be(false)
    expect(File.exist?(File.join(tmpdir, "rabbit-1.0.html.zip"))).to be(false)
  end

  it "moves releases between versions and removes a version nobody uses" do
    old = install_runtime_version(name: "emulatorjs", version: "4.2.2", files: runtime_files, components: { "core" => %w[vice_x64sc] })
    current = installed
    release = create(:release, software: software, runtime_version: old, web_binding: "emulatorjs")

    expect(service.gc(dry_run: true).count).to eq(0)
    service.rebind(name: "emulatorjs", from: "4.2.2", to: "4.2.3", dry_run: false)
    expect(release.reload.runtime_version).to eq(current)

    report = service.gc(dry_run: false)
    expect(report.lines.first).to start_with("Emulatorjs 4.2.2: remove _runtimes/emulatorjs-4.2.2")
    expect(old.reload.deleted_at).to be_present
    expect(File.exist?(File.join(tmpdir, "_runtimes/emulatorjs-4.2.2"))).to be(false)
    expect { service.rebind(name: "emulatorjs", from: "4.2.2", to: "4.2.3") }.to raise_error(ArgumentError, /not installed/)
  end

  it "binds releases that never played on the web to the current version when asked, leaving out the excluded ones" do
    version = installed
    plain = create(:release, software: software, version: "2.0")
    plain.release_assets.create!(kind: "cartridge", path: File.join(tmpdir, "rabbit-2.0.prg"))
    other = create(:release, software: create(:software, name: "net", platform: "c64"), version: "1.0")
    other.release_assets.create!(kind: "cartridge", path: File.join(tmpdir, "net-1.0.prg"))

    expect(service.migrate(dry_run: false).count).to eq(0)
    report = service.migrate(dry_run: false, unplayed: true, exclude: %w[net])

    expect(report.count).to eq(1)
    expect(plain.reload.runtime_version).to eq(version)
    expect(other.reload.runtime_version).to be_nil
  end
end
