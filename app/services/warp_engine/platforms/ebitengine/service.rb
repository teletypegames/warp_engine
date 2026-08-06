module WarpEngine
  module Platforms
    module Ebitengine
      class Service
        include Updatable
        include Builds::BuildWeb
        include Builds::BuildWinX86
        include Builds::BuildWinX64
        include Builds::BuildLinuxX64
        include Builds::BuildMacX64
        include Builds::BuildMacArm64

        label "Ebitengine"
      end
    end
  end
end
