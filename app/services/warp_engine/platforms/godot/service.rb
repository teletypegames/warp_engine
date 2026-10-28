module WarpEngine
  module Platforms
    # The +godot+ platform.
    module Godot
      # Publishes Godot uploads: a required web build, plus Windows x86/x64, Linux
      # x64 and macOS universal zips.
      class Service
        include Updatable
        include Builds::BuildWeb
        include Builds::BuildWinX86
        include Builds::BuildWinX64
        include Builds::BuildLinuxX64
        include Builds::BuildMacUniversal

        label "Godot"
        required_kinds "html"
      end
    end
  end
end
