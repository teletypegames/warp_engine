module WarpEngine
  module Platforms
    module Builds
      # Adds the +win_x86+ kind: the file <tt><name-version>-win-x86.zip</tt>.
      module BuildWinX86
        extend ActiveSupport::Concern

        included do
          register_expected_kind "win_x86"
        end

        private

        # Returns <tt>{ "win_x86" => path }</tt> when the zip exists, else +nil+.
        def win_x86_asset_path(versioned)
          path = full_path("#{versioned}-win-x86.zip")
          { "win_x86" => path } if File.file?(path)
        end
      end
    end
  end
end
