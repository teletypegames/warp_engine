module WarpEngine
  # The runtimes the engine ships, each declared once with the
  # Runtime::Builder DSL. A runtime names no platform; the platforms bind to
  # it in <tt>lib/warp_engine/platform/builtin.rb</tt>.
  class Runtime
    # The EmulatorJS controls the builtin bindings start with: the first
    # player's keyboard keys are left empty, so the keyboard reaches the
    # emulated machine and a gamepad stays the joystick.
    KEYBOARD_TO_MACHINE = {
      "0" => {
        "0" => { "value" => "", "value2" => "BUTTON_2" },
        "1" => { "value" => "", "value2" => "BUTTON_4" },
        "2" => { "value" => "", "value2" => "SELECT" },
        "3" => { "value" => "", "value2" => "START" },
        "4" => { "value" => "", "value2" => "DPAD_UP" },
        "5" => { "value" => "", "value2" => "DPAD_DOWN" },
        "6" => { "value" => "", "value2" => "DPAD_LEFT" },
        "7" => { "value" => "", "value2" => "DPAD_RIGHT" },
        "8" => { "value" => "", "value2" => "BUTTON_1" },
        "9" => { "value" => "", "value2" => "BUTTON_3" },
        "10" => { "value" => "", "value2" => "LEFT_TOP_SHOULDER" },
        "11" => { "value" => "", "value2" => "RIGHT_TOP_SHOULDER" },
        "12" => { "value" => "", "value2" => "LEFT_BOTTOM_SHOULDER" },
        "13" => { "value" => "", "value2" => "RIGHT_BOTTOM_SHOULDER" },
        "14" => { "value" => "", "value2" => "LEFT_STICK" },
        "15" => { "value" => "", "value2" => "RIGHT_STICK" },
        "16" => { "value" => "", "value2" => "LEFT_STICK_X:+1" },
        "17" => { "value" => "", "value2" => "LEFT_STICK_X:-1" },
        "18" => { "value" => "", "value2" => "LEFT_STICK_Y:+1" },
        "19" => { "value" => "", "value2" => "LEFT_STICK_Y:-1" },
        "20" => { "value" => "", "value2" => "RIGHT_STICK_X:+1" },
        "21" => { "value" => "", "value2" => "RIGHT_STICK_X:-1" },
        "22" => { "value" => "", "value2" => "RIGHT_STICK_Y:+1" },
        "23" => { "value" => "", "value2" => "RIGHT_STICK_Y:-1" },
        "24" => { "value" => "" },
        "25" => { "value" => "" },
        "26" => { "value" => "" }
      },
      "1" => {}, "2" => {}, "3" => {}
    }.freeze

    # Returns the controls help rows of the EmulatorJS +joystick+ parameter
    # (a Hash with String keys, see the page template): the joystick's
    # direction keys, its fire key, the key that switches between the
    # joystick and the machine's keyboard and the mode a software starts in.
    # Empty when no joystick key is set.
    def self.joystick_controls(joystick)
      joystick = joystick.to_h
      directions = %w[up down left right].filter_map { |direction| joystick[direction].presence }
      fire = joystick["fire"].presence
      return [] if directions.empty? && fire.nil?

      rows = []
      rows << Controls.row(directions, "Joystick") if directions.any?
      rows << Controls.row(fire, "Fire") if fire
      rows << Controls.row(joystick["toggle"], "Switch between the joystick and the machine's keyboard") if joystick["toggle"].present?
      categories = Array(joystick["categories"]).map(&:to_s)
      rows << Controls.row([], "Starts on the joystick for #{categories.join(', ')} software, on the keyboard otherwise") if categories.any?
      rows
    end

    define :emulatorjs do
      label "EmulatorJS"
      license "GPL-3.0-only"
      version "4.2.3", source: "https://cdn.emulatorjs.org/4.2.3/data/"
      component :core, "cores/%{key}-*wasm.data", "cores/reports/%{key}.json"
      param :core, required: true, component: :core
      param :options, type: :hash, default: {}
      param :controls, type: :hash, default: KEYBOARD_TO_MACHINE
      param :joystick, type: :hash, default: {}
      param :launcher
      param :dos_root, default: "APPS"
      template "emulatorjs.html"
      controls { |params| Runtime.joystick_controls(params["joystick"]) }
    end

    define :tic80 do
      label "TIC-80"
      license "MIT"
      source :upload
      files "tic80.js", "tic80.wasm"
      template "tic80.html"
    end
  end
end
