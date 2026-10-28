module WarpEngine
  module Platforms
    module Builds
      # Adds the +linux_x64+ kind: the file <tt><name-version>-linux-x64.zip</tt>.
      module BuildLinuxX64
        extend ActiveSupport::Concern

        included do
          register_expected_kind "linux_x64"
        end

        private

        # Returns <tt>{ "linux_x64" => path }</tt> when the zip exists, else +nil+.
        def linux_x64_asset_path(versioned)
          path = full_path("#{versioned}-linux-x64.zip")
          { "linux_x64" => path } if File.file?(path)
        end
      end
    end
  end
end
