module WarpEngine
  module SoftwareUpdater
    module Builds
      module BuildDocs
        extend ActiveSupport::Concern

        included do
          register_expected_kind "docs"
          register_prepare_step :prepare_docs
        end

        private

        def prepare_docs(versioned)
          docs_zip = "#{versioned}-docs.zip"
          extract_zip_to_dir(docs_zip, "#{versioned}-docs") if File.file?(full_path(docs_zip))
        end

        def docs_asset_path(versioned)
          docs_dir = "#{versioned}-docs"
          { "docs" => full_path(docs_dir) } if dir_exists?(docs_dir)
        end
      end
    end
  end
end
