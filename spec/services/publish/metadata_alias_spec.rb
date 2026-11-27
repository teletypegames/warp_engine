require "rails_helper"

RSpec.describe WarpEngine::Publish::MetadataReader do
  it "reads the old shelf_name key as directory_name" do
    expect(described_class.canonical({ name: "ariadne", shelf_name: "ARIADNE" })).to eq(name: "ariadne", directory_name: "ARIADNE")
    expect(described_class.canonical({ "shelf_name" => "OLD", "directory_name" => "NEW" })).to eq("directory_name" => "NEW")
  end

  it "publishes the old key onto the software's directory name" do
    recorder = WarpEngine::Publish::Recorder.new(WarpEngine::Platform.find!("c64").definition)
    metadata = described_class.canonical({ name: "ariadne", title: "Ariadne", shelf_name: "ariadne" }).slice(*described_class::KEYS)

    release = recorder.record(metadata, "1.0.0", { "package" => "ariadne-1.0.0.prg" })

    expect(release.software.reload.directory_name).to eq("ARIADNE")
  end
end
