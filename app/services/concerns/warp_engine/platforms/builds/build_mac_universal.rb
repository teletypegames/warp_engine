module WarpEngine
  module Platforms
    module Builds
      module BuildMacUniversal
        extend ActiveSupport::Concern

        included do
          register_expected_kind "mac_universal"
        end

        private

        def mac_universal_asset_path(versioned)
          path = full_path("#{versioned}-mac-universal.zip")
          { "mac_universal" => path } if File.file?(path)
        end
      end
    end
  end
end
