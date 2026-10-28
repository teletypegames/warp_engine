module WarpEngine
  module Platforms
    module Builds
      # Adds the +html+ kind: <tt><name-version>.html.zip</tt>, unpacked into the
      # directory <tt><name-version></tt> before the assets are collected.
      module BuildWeb
        extend ActiveSupport::Concern

        included do
          register_expected_kind "html"
          register_prepare_step :prepare_web
        end

        private

        # Unpacks the web build zip into <tt><name-version></tt>, replacing the
        # directory, when the zip was uploaded.
        def prepare_web(versioned)
          web_zip = "#{versioned}.html.zip"
          extract_zip_to_dir(web_zip, versioned) if File.file?(full_path(web_zip))
        end

        # Returns <tt>{ "html" => directory }</tt> when the web build directory exists, else +nil+.
        def html_asset_path(versioned)
          path = full_path(versioned)
          { "html" => path } if dir_exists?(versioned)
        end
      end
    end
  end
end
