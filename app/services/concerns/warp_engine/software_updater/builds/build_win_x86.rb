module WarpEngine
  module SoftwareUpdater
    module Builds
      module BuildWinX86
        extend ActiveSupport::Concern

        included do
          register_expected_kind "win_x86"
        end

        private

        def win_x86_asset_path(versioned)
          path = full_path("#{versioned}-win-x86.zip")
          { "win_x86" => path } if File.file?(path)
        end
      end
    end
  end
end
