module WarpEngine
  module Platforms
    module Builds
      # Linux on 64-bit ARM: Raspberry Pi 4/5, Odroid, and the retro handhelds.
      # Batocera and the ES-family distributions run on these as much as on
      # x86_64, and an x64 binary installs there but will not start — which is
      # why this is a separate kind rather than something linux_x64 can cover.
      #
      # Include this in a platform service only once its pipeline actually
      # produces the artifact: registering the kind makes /api/builds report it
      # as missing for every release until then.
      module BuildLinuxArm64
        extend ActiveSupport::Concern

        included do
          register_expected_kind "linux_arm64"
        end

        private

        def linux_arm64_asset_path(versioned)
          path = full_path("#{versioned}-linux-arm64.zip")
          { "linux_arm64" => path } if File.file?(path)
        end
      end
    end
  end
end
