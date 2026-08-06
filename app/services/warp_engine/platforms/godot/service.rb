module WarpEngine
  module Platforms
    module Godot
      class Service
        include Updatable
        include Builds::BuildWeb
        include Builds::BuildWinX86
        include Builds::BuildWinX64
        include Builds::BuildLinuxX64
        include Builds::BuildMacUniversal

        label "Godot"
      end
    end
  end
end
