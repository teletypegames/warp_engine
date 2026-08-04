module WarpEngine
  module SoftwareUpdater
    module Builds
      module BuildMacX64
        extend ActiveSupport::Concern

        included do
          register_expected_kind "mac_x64"
        end

        private

        def mac_x64_asset_path(versioned)
          path = full_path("#{versioned}-mac-x64.zip")
          { "mac_x64" => path } if File.file?(path)
        end
      end
    end
  end
end
