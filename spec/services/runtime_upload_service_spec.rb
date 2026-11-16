require "rails_helper"
require_relative "../support/runtime_helpers"

RSpec.describe WarpEngine::RuntimeUploadService do
  let(:tmpdir) { Dir.mktmpdir }
  let(:service) { described_class.new }

  before { allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir) }

  after { FileUtils.rm_rf(tmpdir) }

  it "installs the declared files of the zip and ignores the rest" do
    zip = runtime_zip("tic80.js" => "js", "tic80.wasm" => "wasm", "index.html" => "<html>")

    result = service.upload(name: "tic80", version: "1.1.2837", zip_path: zip)

    expect(result.created).to be(true)
    notice = File.size(File.join(tmpdir, "_runtimes/tic80-1.1.2837/LICENSES.txt"))
    expect(result.runtime_version).to have_attributes(source: "upload", path: "_runtimes/tic80-1.1.2837", size_bytes: 6 + notice)
    expect(result.runtime_version.file_digests.keys).to eq(%w[tic80.js tic80.wasm LICENSES.txt])
    expect(Dir.children(File.join(tmpdir, "_runtimes/tic80-1.1.2837"))).to contain_exactly("tic80.js", "tic80.wasm", "LICENSES.txt")
  end

  it "takes the same files again without a change, and refuses other files for the version" do
    service.upload(name: "tic80", version: "1.1", zip_path: runtime_zip("tic80.js" => "js", "tic80.wasm" => "wasm"))

    again = service.upload(name: "tic80", version: "1.1", zip_path: runtime_zip("tic80.js" => "js", "tic80.wasm" => "wasm"))
    expect(again.created).to be(false)

    expect { service.upload(name: "tic80", version: "1.1", zip_path: runtime_zip("tic80.js" => "js2", "tic80.wasm" => "wasm")) }
      .to raise_error(described_class::Conflict)
  end

  it "refuses a zip without a declared file, a downloaded runtime, a bad version and a non-zip" do
    expect { service.upload(name: "tic80", version: "1.1", zip_path: runtime_zip("tic80.js" => "js")) }
      .to raise_error(described_class::Error, /lacks tic80.wasm/)
    expect { service.upload(name: "emulatorjs", version: "9", zip_path: runtime_zip("a" => "b")) }
      .to raise_error(described_class::Error, /downloaded, not uploaded/)
    expect { service.upload(name: "tic80", version: "../1", zip_path: runtime_zip("a" => "b")) }
      .to raise_error(described_class::Error, /malformed version/)
    not_zip = File.join(tmpdir, "x.zip")
    File.write(not_zip, "nope")
    expect { service.upload(name: "tic80", version: "1", zip_path: not_zip) }.to raise_error(described_class::Error, /not a zip/)
  end
end
