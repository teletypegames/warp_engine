module WarpEngine
  module Platforms
    # The +tic80+ (TIC-80) platform.
    module Tic80
      # Publishes TIC-80 uploads: a required <tt>.tic</tt> cartridge, its <tt>.lua</tt>
      # source, a web build, docs, and Windows x64, Linux x64 and macOS x64 zips.
      # The metadata comes from the header comments of the Lua source.
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
        required_kinds "cartridge"

        # Returns <tt>".tic"</tt>.
        def cartridge_ext = ".tic"
        # Returns <tt>".lua"</tt>.
        def source_ext = ".lua"

        private

        # Reads the metadata from the header comments of <tt><name-version>.lua</tt>.
        def parse_metadata(versioned)
          parse_lua_metadata(full_path("#{versioned}.lua"))
        end
      end
    end
  end
end
