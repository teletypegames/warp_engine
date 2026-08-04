module WarpEngine
  module SoftwareUpdater
    class PhaserService
      include Updatable
      include Builds::BuildWeb

      label "Phaser"
    end
  end
end
