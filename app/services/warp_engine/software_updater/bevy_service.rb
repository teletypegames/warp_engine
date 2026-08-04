module WarpEngine
  module SoftwareUpdater
    class BevyService
      include Updatable
      include Builds::BuildWeb
      include Builds::BuildWinX64
      include Builds::BuildLinuxX64

      label "Bevy"
    end
  end
end
