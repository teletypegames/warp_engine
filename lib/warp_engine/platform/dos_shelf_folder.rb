module WarpEngine
  class Platform
    # Reads the folder of a +dos+ program on a +folders+ shelf from the
    # <tt>dos</tt> block of its release metadata:
    #
    #   "dos": { "folder": "DOSINST", "win32_folder": "DOSINSTW", "settings": ["DOSINST.CFG"],
    #            "store_name": "DOSINST", "store_description": "..." }
    #
    # The +cartridge+ kind takes the plain keys, +win_x86+ the <tt>win32_</tt> ones.
    module DosShelfFolder
      # The key prefix and the INFO.INI platform of each kind.
      TARGETS = { "cartridge" => [ "", "DOS" ], "win_x86" => [ "win32_", "WIN32" ] }.freeze

      # Returns the folder spec (+folder+, +settings+, +name+, +description+,
      # +platform+) of asset +kind+ in +metadata+, or +nil+ when the metadata
      # names no folder for it.
      def self.call(metadata, kind)
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
    end
  end
end
