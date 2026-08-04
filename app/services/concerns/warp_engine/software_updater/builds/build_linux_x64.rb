module WarpEngine
  module SoftwareUpdater
    module Builds
      module BuildLinuxX64
        extend ActiveSupport::Concern

        included do
          register_expected_kind "linux_x64"
        end

        private

        def linux_x64_asset_path(versioned)
          path = full_path("#{versioned}-linux-x64.zip")
          { "linux_x64" => path } if File.file?(path)
        end
      end
    end
  end
end
