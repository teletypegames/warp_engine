require "warp_engine/platform/dos_shelf_folder"

module WarpEngine
  # The platforms the engine ships, each declared once with the Platform::Builder
  # DSL: its kinds (what a publish accepts, what the pipeline builds), where its
  # metadata comes from and which CI-neutral template builds it
  # (<tt>lib/warp_engine/ci/platforms/<template>.yaml.erb</tt>).
  class Platform
    define :tic80 do
      label "TIC-80"
      kind :cartridge, ext: ".tic", required: true
      kind :source, ext: ".lua", always: true
      kind :html, always: true
      kind :docs, always: true
      kinds :win_x64, :linux_x64, :mac_x64
      metadata :lua
      version_source "sed -n 's/^-- version: //p' inc/meta/meta.header.lua 2>/dev/null | head -n 1 | tr -d '[:space:]'"
    end

    define :ebitengine do
      label "Ebitengine"
      kind :html, required: true
      kinds :win_x86, :win_x64, :linux_x64, :linux_arm64
      kind :mac_x64, built: false
      kind :mac_arm64, built: false
    end

    define :love do
      label "LÖVE"
      kind :html, required: true
      kinds :win_x64, :linux_x64, :mac_universal
    end

    { c64: "C64", plus4: "Plus/4" }.each do |machine, name|
      define machine do
        label name
        kind :cartridge, ext: ".prg", required: true
        kinds :html, :win_x64, :linux_x64, :mac_arm64
        ci template: "commodore", machine: machine.to_s
      end
    end

    define :godot do
      label "Godot"
      kind :html, required: true
      kinds :win_x86, :win_x64, :linux_x64, :mac_universal
    end

    define :bevy do
      label "Bevy"
      kind :html, required: true
      kinds :win_x64, :linux_x64, :linux_arm64
    end

    define :phaser do
      label "Phaser"
      kind :html, required: true
    end

    define :dos do
      label "DOS"
      kind :cartridge, ext: ".zip", required: true
      kind :win_x86, optional: true
      release_rule :tag
      shelf_folder DosShelfFolder
    end

    # The names of the platforms the engine ships.
    BUILTIN = builtin_definitions.keys.freeze
    # The builtin platform names; see Platform.names for the full list.
    NAMES = BUILTIN
  end
end
