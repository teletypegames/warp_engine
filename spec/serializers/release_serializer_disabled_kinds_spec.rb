require "rails_helper"
require_relative "../support/runtime_helpers"

RSpec.describe WarpEngine::ReleaseSerializer do
  let(:software) { create(:software, name: "gate", platform: "c64") }
  let(:runtime) do
    install_runtime_version(name: "emulatorjs", version: "4.2.3", files: { "loader.js" => "loader" },
                            components: { "core" => %w[vice_x64sc] })
  end
  let(:release) { create(:release, software: software, version: "1.0.0", runtime_version: runtime, web_binding: "emulatorjs") }

  before do
    %w[cartridge docs win_x64 linux_x64].each do |kind|
      release.release_assets.create!(kind: kind, path: "/data/gate/1.0.0/#{kind}")
    end
  end

  def view = described_class.render_as_hash(release.reload)

  it "lists every asset and plays on the web while nothing is disabled" do
    expect(view[:assets].map { |asset| asset[:kind] }).to match_array(%w[cartridge docs win_x64 linux_x64])
    expect(view[:playUrl]).to eq("/play/gate/1.0.0")
  end

  it "leaves out the kinds the software disables, also of releases published before" do
    software.update!(disabled_kinds: %w[win_x64 linux_x64])

    expect(view[:assets].map { |asset| asset[:kind] }).to match_array(%w[cartridge docs])
    expect(view[:playUrl]).to eq("/play/gate/1.0.0")
  end

  it "tells the disabled kinds on the software, for the store engines" do
    software.update!(disabled_kinds: %w[web stores])

    expect(WarpEngine::SoftwareSerializer.render_as_hash(software.reload)[:disabledKinds]).to eq(%w[web stores])
  end

  it "plays nowhere on the web when the software disables web" do
    software.update!(disabled_kinds: %w[web])

    expect(view[:playUrl]).to eq("")
    expect(view[:players]).to eq([])
  end
end
