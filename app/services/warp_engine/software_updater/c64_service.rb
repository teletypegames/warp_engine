module WarpEngine
  module SoftwareUpdater
    class C64Service
      include Updatable
      include Builds::BuildCartridge

      label "C64"

      def cartridge_ext = ".prg"
    end
  end
end
