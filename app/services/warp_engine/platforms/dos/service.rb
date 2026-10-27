module WarpEngine
  module Platforms
    module Dos
      class Service
        include Updatable
        include Builds::BuildCartridge
        include Builds::BuildWinX86

        label "DOS"
        required_kinds "cartridge"
        optional_kinds "win_x86"
        release_rule "tag"

        TARGETS = { "cartridge" => [ "", "DOS" ], "win_x86" => [ "win32_", "WIN32" ] }.freeze

        def self.shelf_folder(metadata, kind)
          dos = metadata.is_a?(Hash) ? metadata["dos"] : nil
          prefix, platform = TARGETS[kind.to_s]
          return nil unless dos.is_a?(Hash) && prefix

          folder = dos["#{prefix}folder"].presence
          return nil unless folder

          { folder:      folder,
            settings:    Array(dos["settings"]),
            name:        dos["#{prefix}store_name"].presence || folder,
            description: dos["#{prefix}store_description"].to_s,
            platform:    platform }
        end

        def cartridge_ext = ".zip"
      end
    end
  end
end
