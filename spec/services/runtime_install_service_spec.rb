require "rails_helper"
require_relative "../support/runtime_helpers"

RSpec.describe WarpEngine::RuntimeInstallService do
  let(:tmpdir) { Dir.mktmpdir }
  let(:files) do
    { "loader.js" => "loader", "cores/vice-wasm.data" => "vice", "cores/reports/vice.json" => "{}",
      "cores/puae-wasm.data" => "puae", "cores/reports/puae.json" => "{}" }
  end
  let(:fetched) { [] }
  let(:fetcher) do
    lambda do |url|
      fetched << url
      files.fetch(url.delete_prefix("https://cdn.example/emu/1.0/"))
    end
  end
  let(:service) { described_class.new(fetcher: fetcher) }
  let(:root) { File.join(tmpdir, "_runtimes/emu-1.0") }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    stub_runtime(:emu, files: files, components: { core: [ "cores/%{key}-*wasm.data", "cores/reports/%{key}.json" ] },
                       params: { core: { required: true, component: :core } })
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "fetches the base files and the asked components, checks them and records the version" do
    result = service.install(name: "emu", components: { "core" => [ "vice" ] })

    expect(result.fetched).to contain_exactly("loader.js", "cores/vice-wasm.data", "cores/reports/vice.json")
    expect(File.read(File.join(root, "cores/vice-wasm.data"))).to eq("vice")
    expect(File.exist?(File.join(root, "cores/puae-wasm.data"))).to be(false)
    version = result.runtime_version
    expect(version).to have_attributes(name: "emu", version: "1.0", source: "download", path: "_runtimes/emu-1.0", size_bytes: 12)
    expect(version.component_keys("core")).to eq([ "vice" ])
  end

  it "keeps what is in place and adds a component without touching the rest" do
    service.install(name: "emu", components: { "core" => [ "vice" ] })
    fetched.clear

    result = service.install(name: "emu", components: { "core" => [ "puae" ] })

    expect(fetched.map { |url| url.split("/").last }).to contain_exactly("puae-wasm.data", "puae.json")
    expect(result.kept).to include("loader.js", "cores/vice-wasm.data")
    expect(result.runtime_version.reload.component_keys("core")).to contain_exactly("vice", "puae")
    expect(result.runtime_version.file_digests.keys).to include("cores/vice-wasm.data", "cores/puae-wasm.data")
  end

  it "writes nothing on a dry run" do
    result = service.install(name: "emu", components: { "core" => [ "vice" ] }, dry_run: true)

    expect(result).to have_attributes(dry_run: true, runtime_version: nil)
    expect(result.fetched.size).to eq(3)
    expect(fetched).to be_empty
    expect(WarpEngine::RuntimeVersion.count).to eq(0)
  end

  it "refuses a download whose digest differs, an unknown component and an uploaded runtime" do
    files["loader.js"] = "tampered"

    expect { service.install(name: "emu") }.to raise_error(described_class::Error, /loader.js: SHA-256/)
    expect { service.install(name: "emu", components: { "core" => [ "snes" ] }) }.to raise_error(described_class::Error, /no core snes/)
    expect { service.install(name: "tic80") }.to raise_error(described_class::Error, /uploaded by a build/)
  end

  it "finds a damaged or missing file" do
    version = service.install(name: "emu", components: { "core" => [ "vice" ] }).runtime_version
    File.write(File.join(root, "loader.js"), "x")
    File.delete(File.join(root, "cores/reports/vice.json"))

    expect(service.verify(version)).to contain_exactly("loader.js", "cores/reports/vice.json")
  end
end
