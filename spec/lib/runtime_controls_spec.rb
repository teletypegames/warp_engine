require "rails_helper"

RSpec.describe WarpEngine::Runtime::Controls do
  def platform(name) = WarpEngine::Platform.find!(name)

  def controls(name, release_params = nil)
    binding = platform(name).web_binding
    binding.controls_for(binding.runtime_object.definition.resolve_params(binding.params, release_params))
  end

  it "describes the C64 joystick from the binding's parameters, then the binding's own rows" do
    expect(controls("c64")).to eq([
      { "keys" => %w[ArrowUp ArrowDown ArrowLeft ArrowRight], "action" => "Joystick" },
      { "keys" => %w[Space], "action" => "Fire" },
      { "keys" => %w[F9], "action" => "Switch between the joystick and the machine's keyboard" },
      { "keys" => [], "action" => "Starts on the joystick for game software, on the keyboard otherwise" },
      { "keys" => %w[Gamepad], "action" => "Joystick" },
      { "keys" => [], "action" => "The other keys type on the machine's keyboard, by key position" }
    ])
    expect(controls("plus4")).to eq(controls("c64"))
  end

  it "follows a release's joystick keys and leaves the joystick out when the release turns it off" do
    wasd = controls("c64", "joystick" => { "up" => "KeyW", "down" => "KeyS", "left" => "KeyA", "right" => "KeyD" })
    expect(wasd.first).to eq("keys" => %w[KeyW KeyS KeyA KeyD], "action" => "Joystick")

    off = controls("c64", "joystick" => { "up" => nil, "down" => nil, "left" => nil, "right" => nil, "fire" => nil })
    expect(off.map { |row| row["action"] }).to eq([ "Joystick", "The other keys type on the machine's keyboard, by key position" ])
    expect(off.first["keys"]).to eq(%w[Gamepad])
  end

  it "gives DOS and TIC-80 their binding rows and the html platforms none" do
    expect(controls("dos")).to eq([ { "keys" => [], "action" => "The keyboard goes straight to the program" } ])
    expect(controls("tic80").map { |row| [ row["keys"], row["action"] ] }).to include([ %w[KeyZ], "A" ], [ %w[KeyS], "Y" ],
                                                                                      [ %w[Escape], "Menu" ])
    expect(platform("godot").web_bindings).to be_empty
  end

  it "lets a host replace a binding's rows" do
    config = WarpEngine::Configuration.new
    config.platform_web :dos, :emulatorjs, controls: [ { keys: %w[KeyM], action: "Mouse" } ]
    allow(WarpEngine).to receive(:config).and_return(config)

    expect(platform("dos").web_binding.controls).to eq([ { "keys" => %w[KeyM], "action" => "Mouse" } ])
  end

  it "names malformed rows, and the builtin bindings have none" do
    expect(described_class.errors("x")).to eq([ "controls must be a list" ])
    expect(described_class.errors([ { "keys" => %w[KeyZ Joy1] }, "row" ]))
      .to eq([ "controls row 1 has no action", "controls row 1: Joy1 is not a KeyboardEvent.code", "controls row 2 must be an object" ])
    expect(WarpEngine::Platform::WebBinding.build(:tic80, controls: [ { "keys" => %w[Nope], "action" => "A" } ]).errors)
      .to eq([ "controls row 1: Nope is not a KeyboardEvent.code" ])

    WarpEngine::Platform.all.flat_map(&:all_web_bindings).each { |binding| expect(binding.errors).to eq([]) }
  end

  it "shows a binding's own rows in the platform description" do
    web = WarpEngine::PlatformDescriptionService.new.describe(platform("tic80"))["web"]
    expect(web.first["controls"]).to include({ "keys" => %w[KeyZ], "action" => "A" })
  end
end
