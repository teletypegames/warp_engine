module WarpEngine
  module Platforms
    module Builds
      # Adds the +mac_universal+ kind: the file <tt><name-version>-mac-universal.zip</tt>.
      module BuildMacUniversal
        extend ActiveSupport::Concern

        included do
          register_expected_kind "mac_universal"
        end

        private

        # Returns <tt>{ "mac_universal" => path }</tt> when the zip exists, else +nil+.
        def mac_universal_asset_path(versioned)
          path = full_path("#{versioned}-mac-universal.zip")
          { "mac_universal" => path } if File.file?(path)
        end
      end
    end
  end
end
