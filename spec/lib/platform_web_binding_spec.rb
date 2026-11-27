require "rails_helper"

RSpec.describe WarpEngine::Platform::WebBinding do
  def platform(name) = WarpEngine::Platform.find!(name)

  it "binds C64 and Plus/4 to EmulatorJS with their VICE cores, DOS to its DOSBox core, TIC-80 to its player" do
    expect(platform("c64").web_binding).to have_attributes(key: "emulatorjs", runtime: "emulatorjs", payload: "package",
                                                           default: true)
    expect(platform("c64").web_binding.params).to include(core: "vice_x64sc")
    expect(platform("plus4").web_binding.params).to include(core: "vice_xplus4")
    expect(platform("tic80").web_binding.runtime).to eq("tic80")
    expect(platform("dos").web_binding).to have_attributes(runtime: "emulatorjs", isolated: true,
                                                           params: include(core: "dosbox_pure", launcher: "dos"))
    expect(platform("godot").web_bindings).to be_empty
  end

  it "takes the core from the platform's libretro core" do
    expect(platform("c64").libretro).to have_attributes(key: "vice_x64sc", file: "vice_x64sc_libretro", name: "VICE x64sc")
    expect(platform("dos").libretro.key).to eq(platform("dos").web_binding.params[:core])
    expect(platform("godot").libretro).to be_nil

    expect do
      WarpEngine::Platform::Builder.new("amiga").instance_eval { web :emulatorjs, core: :libretro }
    end.to raise_error(ArgumentError, /before libretro/)
  end

  it "makes the first binding the default unless another one says so" do
    builder = WarpEngine::Platform::Builder.new("amiga")
    builder.web :emulatorjs, core: "puae"
    builder.web :emulatorjs, as: :fast, core: "puae2021", default: true
    bindings = builder.build.web_bindings

    expect(bindings.map { |binding| [ binding.key, binding.default ] }).to eq([ [ "emulatorjs", false ], [ "fast", true ] ])
    expect { builder.web :emulatorjs, core: "x" }.to raise_error(ArgumentError, /declared twice/)
  end

  it "lets the host add a binding, make it the default and switch another one off" do
    config = WarpEngine::Configuration.new
    config.platform_web :c64, :emulatorjs, as: :fast, core: "vice_x64"
    config.platform_web :c64, :fast, default: true
    config.platform_web :plus4, :emulatorjs, enabled: false
    allow(WarpEngine).to receive(:config).and_return(config)

    expect(platform("c64").web_bindings.map(&:key)).to eq(%w[emulatorjs fast])
    expect(platform("c64").web_binding.key).to eq("fast")
    expect(platform("c64").web_binding("emulatorjs").params[:core]).to eq("vice_x64sc")
    expect(platform("plus4").web_bindings).to be_empty
    expect(platform("plus4").all_web_bindings.map(&:enabled)).to eq([ false ])
  end

  it "merges a host's parameter change into the builtin binding" do
    config = WarpEngine::Configuration.new
    config.platform_web :c64, :emulatorjs, core: "vice_x64", isolated: true
    allow(WarpEngine).to receive(:config).and_return(config)

    expect(platform("c64").web_binding).to have_attributes(isolated: true, params: include(core: "vice_x64", options: be_a(Hash)))
  end

  it "names what is wrong with a binding" do
    expect(described_class.build(:nope).errors).to eq([ "runtime nope is not defined" ])
    expect(described_class.build(:emulatorjs, payload: :floppy).errors)
      .to contain_exactly("payload floppy is not an asset kind", "core is required")
    expect(described_class.build(:emulatorjs, core: "vice_x64sc")).to be_valid
  end
end
