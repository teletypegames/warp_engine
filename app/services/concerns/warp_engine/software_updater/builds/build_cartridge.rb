module WarpEngine
  module SoftwareUpdater
    module Builds
      module BuildCartridge
        extend ActiveSupport::Concern

        included do
          register_expected_kind "cartridge"
        end

        def cartridge_ext
          raise NotImplementedError, "#{self.class} must implement #cartridge_ext"
        end

        private

        def cartridge_asset_path(versioned)
          path = full_path("#{versioned}#{cartridge_ext}")
          { "cartridge" => path } if File.file?(path)
        end
      end
    end
  end
end
