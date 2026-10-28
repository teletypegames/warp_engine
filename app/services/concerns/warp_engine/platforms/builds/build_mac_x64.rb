module WarpEngine
  module Platforms
    module Builds
      # Adds the +mac_x64+ kind: the file <tt><name-version>-mac-x64.zip</tt>.
      module BuildMacX64
        extend ActiveSupport::Concern

        included do
          register_expected_kind "mac_x64"
        end

        private

        # Returns <tt>{ "mac_x64" => path }</tt> when the zip exists, else +nil+.
        def mac_x64_asset_path(versioned)
          path = full_path("#{versioned}-mac-x64.zip")
          { "mac_x64" => path } if File.file?(path)
        end
      end
    end
  end
end
