module WarpEngine
  module Platforms
    module Dos
      class Service
        include Updatable
        include Builds::BuildCartridge
        include Builds::BuildWinX86

        label "DOS"
        required_kinds "cartridge"
        optional_kinds "win_x86"

        def cartridge_ext = ".zip"
      end
    end
  end
end
