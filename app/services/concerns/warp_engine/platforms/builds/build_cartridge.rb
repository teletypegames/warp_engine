module WarpEngine
  module Platforms
    # Concerns that each add one asset kind to a platform service: including one
    # registers the kind in +expected_kinds+ and supplies the
    # <tt><kind>_asset_path</tt> method that finds the uploaded file.
    module Builds
      # Adds the +cartridge+ kind: the file <tt><name-version><cartridge_ext></tt>.
      module BuildCartridge
        extend ActiveSupport::Concern

        included do
          register_expected_kind "cartridge"
        end

        # The file extension of the cartridge, with its dot (for example <tt>".prg"</tt>).
        # Raises NotImplementedError unless the service defines it.
        def cartridge_ext
          raise NotImplementedError, "#{self.class} must implement #cartridge_ext"
        end

        private

        # Returns <tt>{ "cartridge" => path }</tt> when the cartridge file exists, else +nil+.
        def cartridge_asset_path(versioned)
          path = full_path("#{versioned}#{cartridge_ext}")
          { "cartridge" => path } if File.file?(path)
        end
      end
    end
  end
end
