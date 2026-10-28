module WarpEngine
  module Platforms
    module Builds
      # Adds the +win_x64+ kind: the file <tt><name-version>-win-x64.zip</tt>.
      module BuildWinX64
        extend ActiveSupport::Concern

        included do
          register_expected_kind "win_x64"
        end

        private

        # Returns <tt>{ "win_x64" => path }</tt> when the zip exists, else +nil+.
        def win_x64_asset_path(versioned)
          path = full_path("#{versioned}-win-x64.zip")
          { "win_x64" => path } if File.file?(path)
        end
      end
    end
  end
end
