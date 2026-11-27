require "warp_engine/platform/dos_folder"

module WarpEngine
  # The platforms the engine ships, each declared once with the Platform::Builder
  # DSL: its kinds (what a publish accepts, what the pipeline builds), where its
  # metadata comes from and which CI-neutral template builds it
  # (<tt>lib/warp_engine/ci/platforms/<template>.yaml.erb</tt>), and the
  # runtimes its releases play in on the web (WarpEngine::Runtime).
  class Platform
    # The keys the web player of a Commodore machine plays its joystick with
    # (<tt>KeyboardEvent.code</tt> values): the arrows and Space, F9 switching
    # between the joystick and the machine's keyboard. The joystick is on at
    # the start for a software of the +categories+, the keyboard for the rest.
    COMMODORE_JOYSTICK = {
      "up" => "ArrowUp", "down" => "ArrowDown", "left" => "ArrowLeft", "right" => "ArrowRight",
      "fire" => "Space", "toggle" => "F9", "categories" => %w[game]
    }.freeze

    # The controls help of the Commodore machines beside the joystick rows
    # the EmulatorJS runtime generates.
    COMMODORE_CONTROLS = [
      { "keys" => %w[Gamepad], "action" => "Joystick" },
      { "keys" => [], "action" => "The other keys type on the machine's keyboard, by key position" }
    ].freeze

    # The controls help of DOS in EmulatorJS.
    DOS_CONTROLS = [
      { "keys" => [], "action" => "The keyboard goes straight to the program" }
    ].freeze

    # The controls help of the TIC-80 player: the keyboard plays the first
    # gamepad (by key position), gamepads play the four players.
    TIC80_CONTROLS = [
      { "keys" => %w[ArrowUp ArrowDown ArrowLeft ArrowRight], "action" => "D-pad" },
      { "keys" => %w[KeyZ], "action" => "A" },
      { "keys" => %w[KeyX], "action" => "B" },
      { "keys" => %w[KeyA], "action" => "X" },
      { "keys" => %w[KeyS], "action" => "Y" },
      { "keys" => %w[Gamepad], "action" => "Players 1 to 4" },
      { "keys" => %w[Escape], "action" => "Menu" }
    ].freeze

    define :tic80 do
      label "TIC-80"
      kind :package, ext: ".tic", required: true
      kind :source, ext: ".lua", always: true
      kind :html
      kind :docs, always: true
      kinds :win_x64, :linux_x64, :mac_x64
      metadata :lua
      libretro "tic80", name: "TIC-80"
      web :tic80, controls: TIC80_CONTROLS
      version_source "sed -n 's/^-- version: //p' inc/meta/meta.header.lua 2>/dev/null | head -n 1 | tr -d '[:space:]'"
    end

    define :ebitengine do
      label "Ebitengine"
      kind :html, required: true
      kinds :win_x86, :win_x64, :linux_x64, :linux_arm64
      kind :docs, optional: true
      kind :mac_x64, built: false
      kind :mac_arm64, built: false
    end

    define :love do
      label "LÖVE"
      kind :html, required: true
      kinds :win_x64, :linux_x64, :mac_universal
      kind :docs, optional: true
    end

    { c64: [ "C64", "vice_x64sc", "VICE x64sc" ], plus4: [ "Plus/4", "vice_xplus4", "VICE xplus4" ] }.each do |machine, (name, core, core_name)|
      define machine do
        label name
        kind :package, ext: %w[.prg .d64], required: true
        kind :docs, optional: true
        kinds :win_x64, :linux_x64, :mac_arm64
        libretro core, name: core_name
        web :emulatorjs, core: :libretro, options: { "keyboardInput" => "enabled" }, joystick: COMMODORE_JOYSTICK,
                        controls: COMMODORE_CONTROLS
        ci template: "commodore", machine: machine.to_s
        option :build, values: %w[make], description: "make: the repository's Makefile builds <name>.prg (or .d64) instead of ACME on main.asm"
        option :media, values: %w[prg d64], description: "d64: the release is a disk image the Makefile builds; prg (default): a program file"
      end
    end

    define :godot do
      label "Godot"
      kind :html, required: true
      kinds :win_x86, :win_x64, :linux_x64, :mac_universal
      kind :docs, optional: true
    end

    define :bevy do
      label "Bevy"
      kind :html, required: true
      kinds :win_x64, :linux_x64, :linux_arm64
      kind :docs, optional: true
    end

    define :phaser do
      label "Phaser"
      kind :html, required: true
      kind :docs, optional: true
    end

    define :electron do
      label "Electron"
      kind :linux_x64, required: true
      kind :win_x64, optional: true
      kind :docs, optional: true
      kind :mac_x64, built: false
      kind :mac_arm64, built: false
      version_source "sed -n 's/^[[:space:]]*\"version\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' package.json 2>/dev/null | head -n 1",
                     file: "package.json"
    end

    define :golang do
      label "Go"
      variant :cli, default: true do
        kind :cli_linux_x64, required: true
        kind :cli_win_x64, optional: true
        kind :cli_linux_arm64, optional: true
        kind :cli_mac_x64, optional: true
        kind :cli_mac_arm64, optional: true
        kind :docs, optional: true
      end
      variant :gui do
        kind :linux_x64, required: true
        kind :win_x64, optional: true
        kind :linux_arm64, optional: true
        kind :html, optional: true
        kind :docs, optional: true
        kind :mac_x64, built: false
        kind :mac_arm64, built: false
      end
    end

    define :dos do
      label "DOS"
      kind :package, ext: ".zip", required: true
      kind :win_x86, optional: true
      kind :docs, optional: true
      libretro "dosbox_pure", name: "DOSBox Pure"
      web :emulatorjs, core: :libretro, launcher: "dos", isolated: true, controls: DOS_CONTROLS
      release_rule :tag
      directory_folder DosFolder
    end

    { batocera: "Batocera", retroarch: "RetroArch" }.each do |host, name|
      define host do
        label name
        kind :package, ext: ".tar.gz", required: true
        kind :docs, optional: true
        release_rule :tag
        ci template: "store_engine", host: host.to_s
      end
    end

    # The names of the platforms the engine ships.
    BUILTIN = builtin_definitions.keys.freeze
    # The builtin platform names; see Platform.names for the full list.
    NAMES = BUILTIN
  end
end
