module WarpEngine
  module Platforms
    module Builds
      module BuildWeb
        extend ActiveSupport::Concern

        included do
          register_expected_kind "html"
          register_prepare_step :prepare_web
        end

        private

        def prepare_web(versioned)
          extract_zip_to_dir("#{versioned}.html.zip", versioned)
        end

        def html_asset_path(versioned)
          path = full_path(versioned)
          { "html" => path } if dir_exists?(versioned)
        end
      end
    end
  end
end
