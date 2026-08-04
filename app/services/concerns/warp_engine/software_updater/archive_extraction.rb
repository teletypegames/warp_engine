require "zip"
require "fileutils"

module WarpEngine
  module SoftwareUpdater
    module ArchiveExtraction
      private

      def base_path
        @base_path ||= WarpEngine.config.file_container_path
      end

      def full_path(filename)
        File.join(base_path, filename)
      end

      def dir_exists?(dirname)
        File.directory?(full_path(dirname))
      end

      def delete_dir(dirname)
        FileUtils.rm_rf(full_path(dirname))
      end

      def create_dir(dirname)
        FileUtils.mkdir_p(full_path(dirname))
      end

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

      def extract_zip_to_dir(zip_file, dir_name)
        delete_dir(dir_name) if dir_exists?(dir_name)
        create_dir(dir_name)
        unzip_file(zip_file, dir_name)
      end
    end
  end
end
