module WarpEngine
  module Platforms
    module Phaser
      class Service
        include Updatable
        include Builds::BuildWeb

        label "Phaser"
        required_kinds "html"
      end
    end
  end
end
