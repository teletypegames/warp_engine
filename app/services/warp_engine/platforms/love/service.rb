module WarpEngine
  module Platforms
    module Love
      class Service
        include Updatable
        include Builds::BuildWeb
        include Builds::BuildWinX64
        include Builds::BuildLinuxX64
        include Builds::BuildMacUniversal

        label "LÖVE"
        required_kinds "html"
      end
    end
  end
end
