module WarpEngine
  module Platforms
    module Builds
      module BuildSource
        extend ActiveSupport::Concern

        included do
          register_expected_kind "source"
        end

        def source_ext
          raise NotImplementedError, "#{self.class} must implement #source_ext"
        end

        private

        def source_asset_path(versioned)
          path = full_path("#{versioned}#{source_ext}")
          { "source" => path } if File.file?(path)
        end
      end
    end
  end
end
