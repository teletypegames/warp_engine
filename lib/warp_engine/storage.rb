module WarpEngine

  module Storage
    Location = Struct.new(:kind, :path, :url, keyword_init: true) do
      def file? = kind == :file
      def redirect? = kind == :redirect

      def self.file(path) = new(kind: :file, path: path)
      def self.redirect(url) = new(kind: :redirect, url: url)
    end

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

      def reset!
        @local_adapter = nil
      end
    end
  end
end
