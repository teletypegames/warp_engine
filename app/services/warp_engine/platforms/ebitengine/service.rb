module WarpEngine
  module Platforms
    # The +ebitengine+ platform.
    module Ebitengine
      # Publishes Ebitengine uploads: a required web build, plus Windows x86/x64,
      # Linux x64/arm64 and macOS x64/arm64 zips.
      class Service
        include Updatable
        include Builds::BuildWeb
        include Builds::BuildWinX86
        include Builds::BuildWinX64
        include Builds::BuildLinuxX64
        include Builds::BuildLinuxArm64
        include Builds::BuildMacX64
        include Builds::BuildMacArm64

        label "Ebitengine"
        required_kinds "html"
      end
    end
  end
end
