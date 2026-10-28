module WarpEngine
  module Platforms
    module Builds
      # Adds the +linux_arm64+ kind: the file <tt><name-version>-linux-arm64.zip</tt>.
      module BuildLinuxArm64
        extend ActiveSupport::Concern

        included do
          register_expected_kind "linux_arm64"
        end

        private

        # Returns <tt>{ "linux_arm64" => path }</tt> when the zip exists, else +nil+.
        def linux_arm64_asset_path(versioned)
          path = full_path("#{versioned}-linux-arm64.zip")
          { "linux_arm64" => path } if File.file?(path)
        end
      end
    end
  end
end
