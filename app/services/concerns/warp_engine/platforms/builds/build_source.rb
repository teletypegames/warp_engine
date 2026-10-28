module WarpEngine
  module Platforms
    module Builds
      # Adds the +source+ kind: the file <tt><name-version><source_ext></tt>.
      module BuildSource
        extend ActiveSupport::Concern

        included do
          register_expected_kind "source"
        end

        # The file extension of the source, with its dot (for example <tt>".lua"</tt>).
        # Raises NotImplementedError unless the service defines it.
        def source_ext
          raise NotImplementedError, "#{self.class} must implement #source_ext"
        end

        private

        # Returns <tt>{ "source" => path }</tt> when the source file exists, else +nil+.
        def source_asset_path(versioned)
          path = full_path("#{versioned}#{source_ext}")
          { "source" => path } if File.file?(path)
        end
      end
    end
  end
end
