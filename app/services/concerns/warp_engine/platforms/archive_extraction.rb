require "zip"
require "fileutils"

module WarpEngine
  module Platforms
    # Mixin of the platform services (through Updatable): file helpers that work
    # on paths relative to <tt>WarpEngine.config.file_container_path</tt> and unpack
    # uploaded zip archives there.
    module ArchiveExtraction
      private

      # The file container directory, from <tt>WarpEngine.config.file_container_path</tt>.
      def base_path
        @base_path ||= WarpEngine.config.file_container_path
      end

      # Returns +filename+ joined to #base_path.
      def full_path(filename)
        File.join(base_path, filename)
      end

      # Whether +dirname+ is a directory under #base_path.
      def dir_exists?(dirname)
        File.directory?(full_path(dirname))
      end

      # Removes +dirname+ under #base_path with everything in it.
      def delete_dir(dirname)
        FileUtils.rm_rf(full_path(dirname))
      end

      # Creates +dirname+ under #base_path, with its parents.
      def create_dir(dirname)
        FileUtils.mkdir_p(full_path(dirname))
      end

      # Extracts every entry of +zip_filename+ into +dest_dirname+ (both relative
      # to #base_path), creating subdirectories and overwriting existing files.
      def unzip_file(zip_filename, dest_dirname)
        dest = full_path(dest_dirname)
        Zip::File.open(full_path(zip_filename)) do |zip|
          zip.each do |entry|
            entry_dest = File.join(dest, entry.name)
            FileUtils.mkdir_p(File.dirname(entry_dest))
            entry.extract(entry_dest) { true }
          end
        end
      end

      # Replaces the directory +dir_name+ with the contents of +zip_file+: an
      # existing directory is removed first, then the archive is unpacked into it.
      def extract_zip_to_dir(zip_file, dir_name)
        delete_dir(dir_name) if dir_exists?(dir_name)
        create_dir(dir_name)
        unzip_file(zip_file, dir_name)
      end
    end
  end
end
