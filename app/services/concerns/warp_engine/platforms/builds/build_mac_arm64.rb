module WarpEngine
  module Platforms
    module Builds
      module BuildMacArm64
        extend ActiveSupport::Concern

        included do
          register_expected_kind "mac_arm64"
        end

        private

        def mac_arm64_asset_path(versioned)
          path = full_path("#{versioned}-mac-arm64.zip")
          { "mac_arm64" => path } if File.file?(path)
        end
      end
    end
  end
end
