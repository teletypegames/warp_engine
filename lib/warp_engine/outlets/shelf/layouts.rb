require "fileutils"

module WarpEngine
  module Outlets
    class Shelf < Base
      # The two ways a shelf holds its titles. Each layout names an offered
      # item, places its source in the shelf folder, tells whether a placed
      # copy is still there and lists what an old sync left behind.
      # WarpEngine::ShelfService asks the one of its shelf (Layouts.for).
      module Layouts
        # Returns the layout object of the Shelf::Definition +definition+.
        def self.for(definition) = definition.folders? ? Folders.new(definition) : Flat.new(definition)

        # The +flat+ layout: one file a title, named after the software, with an
        # optional preview picture beside it.
        class Flat
          # The Shelf::Definition the layout belongs to.
          attr_reader :definition

          # [definition] the Shelf::Definition
          def initialize(definition)
            @definition = definition
          end

          # Returns <tt>[nil, file name, nil]</tt> for the offered +item+ (a
          # WarpEngine::Catalog::Offer item), or <tt>[reason]</tt> when the
          # software has no usable shelf name.
          def name_for(item)
            file = definition.file_name_for(item.software)
            file ? [ nil, file, nil ] : [ "no usable shelf name" ]
          end

          # Returns +true+: a flat shelf may hold previews.
          def previews? = definition.preview.present?

          # Copies the source of +entry+ to +target+ through
          # WarpEngine::Files.copy_with_crc and sets the entry's +crc32+.
          def place(entry, target)
            entry.crc32 = WarpEngine::Files.copy_with_crc(entry.source, target)
          end

          # Returns +true+ when the file +target+ is there with the +entry+'s size.
          def placed?(entry, target) = File.file?(target) && File.size(target) == entry.size

          # Returns the file names in +directory+ besides the index: everything a
          # sync may have to remove.
          def removable(directory, _previous)
            return [] unless File.directory?(directory)

            Dir.children(directory).select { |name| File.file?(File.join(directory, name)) } - [ IndexFile::NAME ]
          end
        end

        # The +folders+ layout: one folder a title and kind, unpacked from the
        # program zip, with an INFO_FILE and a MANIFEST_FILE written into it.
        class Folders
          # The program description file written into each folder.
          INFO_FILE = "INFO.INI".freeze
          # The file list (<tt>crc32 size path</tt> per file) written into each folder.
          MANIFEST_FILE = "FILES.LST".freeze

          # The Shelf::Definition the layout belongs to.
          attr_reader :definition

          # [definition] the Shelf::Definition
          def initialize(definition)
            @definition = definition
          end

          # Returns <tt>[nil, folder name, folder spec]</tt> for the offered
          # +item+, the spec read by the platform's +shelf_folder+ from the
          # release metadata, or <tt>[reason]</tt> when there is no usable folder.
          def name_for(item)
            folder = folder_for(item)
            return [ "no #{item.kind} folder in the metadata of #{item.release.version}" ] if folder.nil?
            return [ "#{folder[:folder].inspect} is not a usable folder name" ] unless definition.folder_name_valid?(folder[:folder])

            [ nil, folder[:folder], folder ]
          end

          # Returns +false+: a folders shelf holds no previews.
          def previews? = false

          # Unpacks the program folder of +entry+ into <tt>target.NEW</tt>,
          # writes INFO_FILE and MANIFEST_FILE, swaps it in for +target+ and sets
          # the entry's +crc32+ (of the zip). Raises ArgumentError on an unsafe
          # path in the zip.
          def place(entry, target)
            staging = "#{target}.NEW"
            retired = "#{target}.OLD"
            FileUtils.rm_rf([ staging, retired ])
            FileUtils.mkdir_p(staging)

            unpack(entry, staging)
            File.binwrite(File.join(staging, INFO_FILE), info_text(entry))
            File.binwrite(File.join(staging, MANIFEST_FILE), manifest_text(staging))
            FileUtils.chmod_R("a+rX", staging)

            File.rename(target, retired) if File.exist?(target)
            File.rename(staging, target)
            FileUtils.rm_rf(retired)
            entry.crc32 = WarpEngine::Files.crc32(entry.source)
          ensure
            FileUtils.rm_rf(staging) if staging && File.exist?(staging)
          end

          # Returns +true+ when the folder +target+ is there.
          def placed?(_entry, target) = File.directory?(target)

          # Returns the folders of the +previous+ index that are still in
          # +directory+: a folders shelf removes only what it wrote.
          def removable(directory, previous)
            previous.keys.select { |name| File.directory?(File.join(directory, name)) }
          end

          private

          def folder_for(item)
            metadata = item.metadata
            return nil if metadata.nil?

            WarpEngine::Platform.find(definition.platform)&.shelf_folder(metadata, item.kind)&.to_h&.symbolize_keys
          end

          def unpack(entry, staging)
            prefix = "#{entry.folder[:folder]}/"
            settings = Array(entry.folder[:settings]).map(&:to_s)
            Zip::File.open(entry.source) do |zip|
              zip.each do |item|
                next if item.directory? || !item.name.start_with?(prefix)

                relative = item.name.delete_prefix(prefix)
                parts = relative.split("/")
                raise ArgumentError, "unsafe path in #{entry.source}: #{item.name}" if relative.empty? || parts.include?("..") || parts.include?("")
                next if settings.include?(relative) || [ INFO_FILE, MANIFEST_FILE ].include?(relative)

                destination = File.join(staging, relative)
                FileUtils.mkdir_p(File.dirname(destination))
                File.binwrite(destination, item.get_input_stream.read)
              end
            end
          end

          def info_text(entry)
            folder = entry.folder
            clean = WarpEngine::ShelfService.method(:clean)
            [ "[program]",
              "name=#{clean.call(folder[:name].presence || folder[:folder])}",
              "description=#{clean.call(folder[:description])}",
              "version=#{entry.version}",
              ("platform=#{clean.call(folder[:platform])}" if folder[:platform].present?) ].compact.map { |line| "#{line}\r\n" }.join
          end

          def manifest_text(staging)
            Dir.glob("**/*", base: staging).select { |relative| File.file?(File.join(staging, relative)) }
               .reject { |relative| relative == MANIFEST_FILE }.sort
               .map do |relative|
                 path = File.join(staging, relative)
                 "#{WarpEngine::Files.crc32(path)} #{File.size(path)} #{relative}\r\n"
               end.join
          end
        end
      end
    end
  end
end
