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

        def parse_lua_metadata(source_path)
          metadata = {}
          File.foreach(source_path) do |line|
            break unless line.start_with?("--")
            parts = line[2..].split(":", 2)
            next if parts.length != 2
            key   = parts[0].strip.downcase.to_sym
            value = parts[1].strip
            metadata[key] = value
          end
          metadata.slice(*MetadataParsing::METADATA_KEYS)
        end
      end
    end
  end
end
