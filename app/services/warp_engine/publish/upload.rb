module WarpEngine
  module Publish
    # The files a CI uploaded for one release: the software +name+, the
    # +version+ and the +root+ of the file container they are in.
    Upload = ::Data.define(:name, :version, :root) do
      # Returns <tt>name-version</tt>, the prefix of every uploaded file.
      def versioned = "#{name}-#{version}"

      # Returns the absolute path of +file+ in the file container.
      def path(file) = File.join(root, file)
    end
  end
end
