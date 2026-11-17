require "rails_helper"
require_relative "../../support/runtime_helpers"

RSpec.describe WarpEngine::Publish::WebBinder do
  let(:tmpdir) { Dir.mktmpdir }
  let(:c64) { WarpEngine::Platform.find!("c64") }
  let(:release) { create(:release, software: create(:software, platform: "c64")) }

  before { allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir) }

  after { FileUtils.rm_rf(tmpdir) }

  def emulatorjs(cores) = install_runtime_version(name: "emulatorjs", version: "4.2.3", files: { "loader.js" => "x" },
                                                  components: { "core" => cores })

  it "binds the release to the platform's default binding in the current runtime version" do
    version = emulatorjs(%w[vice_x64sc])

    expect(described_class.new(c64).bind(release, nil)).to eq(version)
    expect(release.reload).to have_attributes(runtime_version: version, web_binding: "emulatorjs", web_options: nil)
  end

  it "keeps the web section's options and the binding it names" do
    version = emulatorjs(%w[vice_x64sc])
    web = { "runtime" => "emulatorjs", "params" => { "options" => { "x" => 1 } }, "start" => "GO.EXE", "other" => 1 }

    described_class.new(c64).bind(release, web)

    expect(release.reload).to have_attributes(runtime_version: version,
                                              web_options: { "params" => { "options" => { "x" => 1 } }, "start" => "GO.EXE" })
  end

  it "leaves the release unbound when the runtime or the core is not installed, or the metadata says no" do
    expect(described_class.new(c64).bind(release, nil)).to be_nil

    emulatorjs(%w[vice_xplus4])
    expect(described_class.new(c64).bind(release, nil)).to be_nil

    WarpEngine::RuntimeVersion.last.runtime_components.create!(kind: "core", key: "vice_x64sc")
    expect(described_class.new(c64).bind(release, { "enabled" => false })).to be_nil
    expect(release.reload).to have_attributes(web_binding: nil, web_options: { "enabled" => false })
    expect(described_class.new(c64).bind(release, { "runtime" => "nope" })).to be_nil
    expect(described_class.new(WarpEngine::Platform.find!("godot")).bind(release, nil)).to be_nil
  end

  it "binds on publish, from the metadata.json web section" do
    version = emulatorjs(%w[vice_x64sc])
    FileUtils.mkdir_p(File.join(tmpdir, "rabbit", "1.0"))
    File.write(File.join(tmpdir, "rabbit", "1.0", "rabbit-1.0.metadata.json"),
               { name: "rabbit", title: "Rabbit", web: { params: { options: { "speed" => "1" } } } }.to_json)
    File.binwrite(File.join(tmpdir, "rabbit", "1.0", "rabbit-1.0.prg"), "\x01\x08")

    published = c64.publish("rabbit", "1.0").reload

    expect(published).to have_attributes(runtime_version: version, web_binding: "emulatorjs")
    expect(published.web_options).to eq("params" => { "options" => { "speed" => "1" } })
    expect(published.software.attributes).not_to have_key("web")
  end
end
