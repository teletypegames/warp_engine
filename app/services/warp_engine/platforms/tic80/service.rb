module WarpEngine
  module Platforms
    module Tic80
      class Service
        include Updatable
        include Builds::BuildCartridge
        include Builds::BuildSource
        include Builds::BuildWeb
        include Builds::BuildDocs
        include Builds::BuildWinX64
        include Builds::BuildLinuxX64
        include Builds::BuildMacX64

        label "TIC-80"

        def cartridge_ext = ".tic"
        def source_ext = ".lua"

        private

        def parse_metadata(versioned)
          parse_lua_metadata(full_path("#{versioned}.lua"))
        end
      end
    end
  end
end
