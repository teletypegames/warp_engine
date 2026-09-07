module WarpEngine
  module Platforms
    module Plus4
      class Service
        include Updatable
        include Builds::BuildCartridge

        label "Plus/4"

        def cartridge_ext = ".prg"
      end
    end
  end
end
