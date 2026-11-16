require "rails_helper"

RSpec.describe WarpEngine::Publish::Recorder do
  let(:recorder) { described_class.new(WarpEngine::Platform.find!("c64").definition) }
  let(:metadata) { { name: "ariadne", title: "Ariadne" } }

  before { WarpEngine::SoftwareStatus.seed_defaults! }

  it "brings back a deleted software and a deleted release of the same version" do
    first = recorder.record(metadata, "1.0.0", { "cartridge" => "ariadne-1.0.0.prg" })
    first.software.soft_delete!
    first.soft_delete!

    again = recorder.record(metadata, "1.0.0", { "cartridge" => "ariadne-1.0.0.prg" })

    expect(again.id).to eq(first.id)
    expect(again.reload).not_to be_discarded
    expect(again.software).not_to be_discarded
    expect(WarpEngine::Software.kept.find_by(name: "ariadne").releases).to eq([ again ])
  end
end
