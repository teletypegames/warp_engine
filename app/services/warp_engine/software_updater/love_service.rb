module WarpEngine
  module SoftwareUpdater
    class LoveService
      include Updatable
      include Builds::BuildWeb
      include Builds::BuildWinX64
      include Builds::BuildLinuxX64
      include Builds::BuildMacUniversal

      label "LÖVE"
    end
  end
end
