module WarpEngine
  module Platforms
    module Phaser
      class Service
        include Updatable
        include Builds::BuildWeb

        label "Phaser"
      end
    end
  end
end
