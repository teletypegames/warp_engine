module WarpEngine
  module Platforms
    # The +plus4+ (Commodore Plus/4) platform.
    module Plus4
      # Publishes Plus/4 uploads: a required <tt>.prg</tt> cartridge, plus a web build
      # and Windows x64, Linux x64 and macOS arm64 zips.
      class Service
        include Updatable
        include Builds::BuildCartridge
        include Builds::BuildWeb
        include Builds::BuildWinX64
        include Builds::BuildLinuxX64
        include Builds::BuildMacArm64

        label "Plus/4"
        required_kinds "cartridge"

        # Returns <tt>".prg"</tt>.
        def cartridge_ext = ".prg"
      end
    end
  end
end
