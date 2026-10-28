module WarpEngine
  module Platforms
    module Builds
      # Adds the +docs+ kind: <tt><name-version>-docs.zip</tt>, unpacked into the
      # directory <tt><name-version>-docs</tt> before the assets are collected.
      module BuildDocs
        extend ActiveSupport::Concern

        included do
          register_expected_kind "docs"
          register_prepare_step :prepare_docs
        end

        private

        # Unpacks the docs zip into <tt><name-version>-docs</tt>, replacing the
        # directory, when the zip was uploaded.
        def prepare_docs(versioned)
          docs_zip = "#{versioned}-docs.zip"
          extract_zip_to_dir(docs_zip, "#{versioned}-docs") if File.file?(full_path(docs_zip))
        end

        # Returns <tt>{ "docs" => directory }</tt> when the docs directory exists, else +nil+.
        def docs_asset_path(versioned)
          docs_dir = "#{versioned}-docs"
          { "docs" => full_path(docs_dir) } if dir_exists?(docs_dir)
        end
      end
    end
  end
end
