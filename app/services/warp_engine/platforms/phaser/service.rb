module WarpEngine
  module Platforms
    # The +phaser+ platform.
    module Phaser
      # Publishes Phaser uploads: a required web build.
      class Service
        include Updatable
        include Builds::BuildWeb

        label "Phaser"
        required_kinds "html"
      end
    end
  end
end
