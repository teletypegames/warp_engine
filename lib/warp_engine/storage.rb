module WarpEngine
  # Where the artifacts physically live.
  #
  # Until now every path in the engine was a local filesystem path. This module
  # is the seam a host needs to serve builds from somewhere else (an object
  # store behind a CDN, for example) without patching the engine.
  #
  # The default adapter is :local and behaves exactly as before - same paths,
  # same traversal protection, same File.file? checks.
  #
  # A custom adapter is any object answering to this contract:
  #
  #   file?(relative_path)       -> true/false
  #   directory?(relative_path)  -> true/false
  #   locate(relative_path, filename: nil, expires_in: nil) -> Location
  #
  # It is set on the configuration:
  #
  #   c.storage_adapter = MyObjectStore.new   # or :local (default)
  #
  # NOTE: ingestion (build/upload, archive extraction, the admin file manager)
  # still writes to the local filesystem. A remote adapter therefore needs its
  # own upload path today; the serving side is what this seam covers.
  module Storage
    Location = Struct.new(:kind, :path, :url, keyword_init: true) do
      def file? = kind == :file
      def redirect? = kind == :redirect

      def self.file(path) = new(kind: :file, path: path)
      def self.redirect(url) = new(kind: :redirect, url: url)
    end

    # The local filesystem, rooted at config.file_container_path.
    class LocalAdapter
      def base_path
        Pathname.new(WarpEngine.config.file_container_path)
      end

      def absolute_path(relative_path)
        base_path.join(relative_path.to_s)
      end

      def file?(relative_path)
        path = absolute_path(relative_path)
        File.file?(path) && inside_base?(path)
      end

      def directory?(relative_path)
        path = absolute_path(relative_path)
        File.directory?(path) && inside_base?(path)
      end

      # expires_in is part of the contract for signing adapters; the local
      # filesystem has nothing to sign, so it is ignored here.
      def locate(relative_path, filename: nil, expires_in: nil)
        Location.file(absolute_path(relative_path).to_s)
      end

      private

      # Path traversal guard: the resolved path must stay under the container.
      def inside_base?(path)
        root = base_path.realpath.to_s
        Pathname.new(path).realpath.to_s.start_with?(root)
      rescue Errno::ENOENT
        false
      end
    end

    class << self
      def adapter
        configured = WarpEngine.config.storage_adapter

        case configured
        when nil, :local, "local" then local_adapter
        else configured
        end
      end

      def local? = adapter.is_a?(LocalAdapter)

      def local_adapter
        @local_adapter ||= LocalAdapter.new
      end

      # Tests and hosts that swap the configuration at runtime.
      def reset!
        @local_adapter = nil
      end
    end
  end
end
