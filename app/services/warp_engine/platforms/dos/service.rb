module WarpEngine
  module Platforms
    # The +dos+ platform.
    module Dos
      # Publishes DOS uploads: a required cartridge zip and an optional Windows x86
      # zip, released on tags. Serves a +folders+ shelf through ::shelf_folder.
      class Service
        include Updatable
        include Builds::BuildCartridge
        include Builds::BuildWinX86

        label "DOS"
        required_kinds "cartridge"
        optional_kinds "win_x86"
        release_rule "tag"

        # The shelf folder settings of each kind: the key prefix in the +dos+ block of
        # the metadata and the +platform+ written to <tt>INFO.INI</tt>.
        TARGETS = { "cartridge" => [ "", "DOS" ], "win_x86" => [ "win32_", "WIN32" ] }.freeze

        # Returns the folder spec of a +folders+ shelf for asset +kind+ from the +dos+
        # block of the uploaded +metadata+ (a Hash with string keys): <tt>folder</tt>,
        # <tt>store_name</tt> and <tt>store_description</tt> for the +cartridge+,
        # the same keys with a <tt>win32_</tt> prefix for +win_x86+, and the shared
        # <tt>settings</tt> list.
        #
        # Returns a Hash with +folder+, +settings+, +name+ (the store name, or the
        # folder), +description+ and +platform+ (<tt>"DOS"</tt> or <tt>"WIN32"</tt>), or
        # +nil+ when the block, the kind or the folder is missing.
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

        # Returns <tt>".zip"</tt>.
        def cartridge_ext = ".zip"
      end
    end
  end
end
