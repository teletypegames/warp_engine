module WarpEngine
  module Platforms
    # The +love+ (LÖVE) platform.
    module Love
      # Publishes LÖVE uploads: a required web build, plus Windows x64, Linux x64
      # and macOS universal zips.
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
