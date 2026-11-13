require "fileutils"
require "zip"

module WarpEngine
  module Publish
    # Unpacks an uploaded zip (a web build, the docs) into a directory of the
    # file container.
    class Unpacker
      # Replaces the directory +dir+ with the content of the zip +zip_path+.
      # Raises WarpEngine::Error when an entry would land outside +dir+ (a
      # <tt>../</tt> or absolute name), before anything of it is written.
      def replace_dir(zip_path, dir)
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
        root = File.realpath(dir)
        Zip::File.open(zip_path) do |zip|
          zip.each do |entry|
            target = File.expand_path(entry.name, root)
            raise WarpEngine::Error, "unsafe path in #{File.basename(zip_path)}: #{entry.name}" unless target.start_with?("#{root}/")

            FileUtils.mkdir_p(File.dirname(target))
            entry.directory? ? FileUtils.mkdir_p(target) : entry.extract(target) { true }
          end
        end
      end
    end
  end
end
