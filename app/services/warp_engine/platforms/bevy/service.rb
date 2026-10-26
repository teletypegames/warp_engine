module WarpEngine
  module Platforms
    module Bevy
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
