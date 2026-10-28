module WarpEngine
  module Platforms
    # The +bevy+ platform.
    module Bevy
      # Publishes Bevy uploads: a required web build, plus Windows x64 and Linux
      # x64/arm64 zips.
      class Service
        include Updatable
        include Builds::BuildWeb
        include Builds::BuildWinX64
        include Builds::BuildLinuxX64
        include Builds::BuildLinuxArm64

        label "Bevy"
        required_kinds "html"
      end
    end
  end
end
