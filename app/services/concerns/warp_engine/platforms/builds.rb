module WarpEngine
  module Platforms
    # One module per WarpEngine::AssetKinds kind (+BuildCartridge+,
    # +BuildWinX64+, ...) for legacy Updatable services: including one
    # registers the kind. Deprecated with Updatable; the file names and
    # unpacking now come from the WarpEngine::AssetKind.
    module Builds
      # Returns a module that registers +kind+ on the Updatable class including it.
      def self.module_for(kind)
        Module.new do
          extend ActiveSupport::Concern

          included { register_expected_kind kind }
        end
      end

      # The legacy module of the +cartridge+ kind.
      BuildCartridge = module_for("cartridge")
      # The legacy module of the +source+ kind.
      BuildSource = module_for("source")
      # The legacy module of the +html+ kind.
      BuildWeb = module_for("html")
      # The legacy module of the +docs+ kind.
      BuildDocs = module_for("docs")
      # The legacy module of the +win_x86+ kind.
      BuildWinX86 = module_for("win_x86")
      # The legacy module of the +win_x64+ kind.
      BuildWinX64 = module_for("win_x64")
      # The legacy module of the +linux_x64+ kind.
      BuildLinuxX64 = module_for("linux_x64")
      # The legacy module of the +linux_arm64+ kind.
      BuildLinuxArm64 = module_for("linux_arm64")
      # The legacy module of the +mac_x64+ kind.
      BuildMacX64 = module_for("mac_x64")
      # The legacy module of the +mac_arm64+ kind.
      BuildMacArm64 = module_for("mac_arm64")
      # The legacy module of the +mac_universal+ kind.
      BuildMacUniversal = module_for("mac_universal")
    end
  end
end
