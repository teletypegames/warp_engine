module WarpEngine
  module Outlets
    class Shelf < Base
      # One validated shelf definition.
      #
      # [platform]    the platform name
      # [kinds]       the release asset kinds it takes
      # [layout]      +flat+ or +folders+
      # [path]        the folder, relative to +file_container_path+
      # [extension]   the extension of a flat shelf's files, in capitals
      # [name_length] the longest file name (extension included) or folder name
      # [statuses]    the software statuses listed; empty means the default visible ones
      # [urls]        where the host serves the folder
      # [preview]     the WarpEngine::ShelfPreview format written beside each
      #               title of a flat shelf, or +nil+ for none
      Definition = Struct.new(:platform, :kinds, :layout, :path, :extension, :name_length, :statuses, :urls, :preview,
                         keyword_init: true) do
        # Returns the absolute path of the shelf folder.
        def directory
          File.join(WarpEngine.config.file_container_path, path)
        end

        # Returns +true+ for a +folders+ layout.
        def folders? = layout == "folders"

        # Returns the longest name without the extension.
        def base_length = folders? ? name_length : name_length - extension.length

        # Returns the shelf file name of +software+: its +shelf_name+ or +name+,
        # normalized, cut to #base_length, plus the extension; +nil+ when nothing
        # of the name is left.
        def file_name_for(software)
          base = Definitions.normalize_name(software.shelf_name.presence || software.name)
          base = base[0, base_length].sub(/-+\z/, "")
          base.empty? ? nil : "#{base}#{extension}"
        end

        # Returns the WarpEngine::ShelfPreview renderer class of the shelf, or +nil+.
        def preview_renderer = preview && WarpEngine::ShelfPreview.for(preview)

        # Returns the name of the preview beside the shelf file +file+: the file
        # name with the extension of the renderer (<tt>ARIADNE.PVW</tt>).
        def preview_name_for(file) = "#{file.delete_suffix(extension)}#{preview_renderer::EXTENSION}"

        # Returns +true+ when +name+ is a String of the allowed characters (Definitions::NAME_PATTERN) no
        # longer than +name_length+.
        def folder_name_valid?(name)
          name.is_a?(String) && name.match?(Definitions::NAME_PATTERN) && name.length <= name_length
        end

        # Returns the status keys the shelf lists: +statuses+, or the default
        # visible keys of WarpEngine::SoftwareStatus.
        def listed_statuses
          statuses.presence || WarpEngine::SoftwareStatus.default_visible_keys
        end

        # Returns a one-line description, e.g. <tt>c64 (cartridge, flat)</tt>.
        def describe = "#{platform} (#{kinds.join(', ')}, #{layout})"
      end
    end
  end
end
