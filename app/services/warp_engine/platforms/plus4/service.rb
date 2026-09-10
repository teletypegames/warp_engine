module WarpEngine
  module Platforms
    module Plus4
      class Service
        include Updatable
        include Builds::BuildCartridge
        include Builds::BuildWeb
        include Builds::BuildWinX64
        include Builds::BuildLinuxX64
        include Builds::BuildMacArm64

        label "Plus/4"

        def cartridge_ext = ".prg"
      end
    end
  end
end
