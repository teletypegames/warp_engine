module WarpEngine
  # The storage adapter that serves build artifacts. The default is
  # LocalAdapter (the filesystem under +file_container_path+); a host can set
  # any object answering +file?+, +directory?+ and +locate+ with +storage+.
  module Storage
    # Where a stored file is served from: +kind+ is +:file+ (an absolute +path+
    # the engine sends) or +:redirect+ (a +url+ the engine redirects to).
    # Build one with <tt>Location.file(path)</tt> or <tt>Location.redirect(url)</tt>;
    # +file?+ and +redirect?+ tell the two apart.
    Location = Struct.new(:kind, :path, :url, keyword_init: true) do
      def file? = kind == :file
      def redirect? = kind == :redirect

      def self.file(path) = new(kind: :file, path: path)
      def self.redirect(url) = new(kind: :redirect, url: url)
    end

    # The default storage adapter: files under +file_container_path+ on the
    # local disk. Paths resolving outside that directory count as missing.
    class LocalAdapter
      # Returns the configured +file_container_path+ as a Pathname.
      def base_path
        Pathname.new(WarpEngine.config.file_container_path)
      end

      # Returns +relative_path+ joined onto #base_path, without any check.
      def absolute_path(relative_path)
        base_path.join(relative_path.to_s)
      end

      # Returns +true+ when +relative_path+ is a file inside #base_path.
      def file?(relative_path)
        path = absolute_path(relative_path)
        File.file?(path) && inside_base?(path)
      end

      # Returns +true+ when +relative_path+ is a directory inside #base_path.
      def directory?(relative_path)
        path = absolute_path(relative_path)
        File.directory?(path) && inside_base?(path)
      end

      # Returns a Location.file with the absolute path of +relative_path+; the
      # +filename+ and +expires_in+ hints are ignored.
      def locate(relative_path, filename: nil, expires_in: nil)
        Location.file(absolute_path(relative_path).to_s)
      end

      private

      def inside_base?(path)
        root = base_path.realpath.to_s
        Pathname.new(path).realpath.to_s.start_with?(root)
      rescue Errno::ENOENT
        false
      end
    end

    class << self
      # Returns the Mime::Type for the extension of +path+, or
      # <tt>"application/octet-stream"</tt> when it is unknown.
      def mime_for(path)
        ext = File.extname(path.to_s).delete_prefix(".")
        Mime::Type.lookup_by_extension(ext) || "application/octet-stream"
      end

      # Returns the configured storage adapter; +nil+, +:local+ or <tt>"local"</tt>
      # give the shared LocalAdapter instance.
      def adapter
        configured = WarpEngine.config.storage_adapter

        case configured
        when nil, :local, "local" then local_adapter
        else configured
        end
      end

      # Returns +true+ when the adapter is a LocalAdapter.
      def local? = adapter.is_a?(LocalAdapter)

      # Returns the memoized LocalAdapter instance.
      def local_adapter
        @local_adapter ||= LocalAdapter.new
      end

      # Drops the memoized LocalAdapter instance.
      def reset!
        @local_adapter = nil
      end
    end
  end
end
