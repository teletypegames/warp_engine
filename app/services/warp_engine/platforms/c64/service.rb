module WarpEngine
  module Platforms
    module C64
      class Service
        include Updatable
        include Builds::BuildCartridge

        label "C64"

        def cartridge_ext = ".prg"
      end
    end
  end
end
