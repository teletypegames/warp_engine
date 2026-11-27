require "fileutils"

module WarpEngine
  module Feeds
    class Directory < Base
      # Builds one directory (a WarpEngine::Feeds::Directory): the folder that holds
      # the latest build of every listed title of a platform under a fixed
      # name, with an <tt>INDEX.TXT</tt> listing them. A +flat+ directory holds one
      # file a title, a +folders+ directory one folder a title and kind. A flat
      # directory with a +preview+ also holds a picture of each title that has an
      # image, made by its Directory::Preview renderer.
      #
      # The builder plans and orchestrates: Directory::IndexFile reads and writes
      # the index, Directory::Layouts names and places the titles, and
      # WarpEngine::Files does the atomic writes and checksums.
      class Builder
        # The longest index line, in bytes; the description is cut to fit.
        LINE_LIMIT = 255

        # One title and kind on the directory: the directory +file+ (or folder) name, the
        # asset +kind+, +version+, +size+ and +crc32+ of the source, the +title+,
        # +author+, +description+ and +category+ of the software, the +year+ the
        # release was made, the +source+ path, the +software+, on a +folders+
        # directory the +folder+ spec, and the
        # +preview+ file name with the +preview_source+ image it is made from
        # (both +nil+ without a preview).
        Entry = Struct.new(:file, :kind, :version, :size, :crc32, :title, :author, :description, :source, :software,
                           :folder, :category, :year, :preview, :preview_source, keyword_init: true) do
          # The index line of the entry:
          # <tt>file|version|size|crc32|title|author|description|category|preview</tt>,
          # cleaned with WarpEngine::Names.clean; the description is
          # cut so that the line fits in LINE_LIMIT bytes.
          def line
            fields = [ file, version, size, crc32, Names.clean(title), Names.clean(author) ]
            head = fields.join("|") + "|"
            tail = "|#{Names.clean(category)}|#{preview}"
            head + Names.clean(description)[0, [ LINE_LIMIT - head.bytesize - tail.bytesize, 0 ].max] + tail
          end
        end

        # The outcome of #sync!: the +directory+, the +entries+ on it, the +skipped+
        # softwares, the entries +written+, the file names +removed+, and whether the
        # index text changed.
        Result = Struct.new(:directory, :entries, :skipped, :written, :removed, :index_changed, keyword_init: true) do
          # Whether the sync wrote a file, removed one or changed the index.
          def changed? = index_changed || written.any? || removed.any?

          # Returns what the sync did, one line a file written or removed, then
          # the index, as <tt>rake warp_engine:feeds:sync</tt> prints it.
          def lines
            written.map { |entry| "  write   #{entry.file} #{entry.version}" } +
              removed.map { |file| "  remove  #{file}" } +
              [ "  index   #{index_changed ? 'rewritten' : 'unchanged'}" ]
          end
        end

        # The WarpEngine::Feeds::Directory being built.
        attr_reader :directory

        # [directory] the WarpEngine::Feeds::Directory to build
        def initialize(directory)
          @directory = directory
          @layout = Layouts.for(directory)
          @index = IndexFile.new(directory.directory)
        end

        # Returns the WarpEngine::Catalog::Selection of the directory (Directory#selection).
        def selection = directory.selection

        # Decides what the directory holds, without touching the disk: what #selection
        # offers, each item named for the directory by its layout. A name already taken
        # (by an older software) skips the newer one.
        #
        # Returns <tt>[entries, skipped]</tt>: the Entry list sorted by title, and the
        # WarpEngine::Catalog::Selection::Skip list.
        def plan
          entries = []
          skipped = []
          taken = {}

          selection.candidates.each do |software|
            found, reasons = consider(software)
            skipped << WarpEngine::Catalog::Selection::Skip.new(software: software, reason: reasons.join("; ")) if found.empty?

            found.each do |entry|
              if taken.key?(entry.file)
                skipped << WarpEngine::Catalog::Selection::Skip.new(software: software, reason: "#{entry.file} is taken by #{taken[entry.file].name}")
              else
                taken[entry.file] = software
                entries << entry
              end
            end
          end

          [ entries.sort_by { |entry| [ entry.title.to_s.downcase, entry.file ] }, skipped ]
        end

        # Brings the directory folder in line with #plan, under an exclusive file lock:
        # places (copies or unpacks) the entries whose version, size or source
        # changed, renders the previews that are missing or older than their entry
        # or image (an image that cannot be rendered leaves the entry without a
        # preview and is logged), replaces the index when its text changes, then
        # removes the files (or, on a +folders+ directory, the formerly listed folders)
        # that left the directory. Entries not rewritten keep the CRC32 of the previous
        # index.
        #
        # [dry_run] when +true+, only computes the Result and writes nothing
        #
        # Returns a Result. Raises ArgumentError when a folder zip holds an unsafe path.
        def sync!(dry_run: false)
          entries, skipped = plan
          with_lock do
            previous = @index.entries
            written = entries.select { |entry| stale?(entry, previous[entry.file]) }
            (entries - written).each { |entry| entry.crc32 = previous.dig(entry.file, :crc32) }
            removed = @layout.removable(directory.directory, previous) - entries.map(&:file) - entries.filter_map(&:preview)

            index_changed = @index.changed?(entries)
            unless dry_run
              FileUtils.mkdir_p(directory.directory)
              written.each { |entry| @layout.place(entry, target(entry.file)) }
              entries.each { |entry| place_preview(entry, written.include?(entry)) if entry.preview }
              index_changed = @index.write(entries)
              removed.each { |file| FileUtils.rm_rf(target(file)) }
            end

            Result.new(directory: directory, entries: entries, skipped: skipped, written: written,
                       removed: removed, index_changed: index_changed)
          end
        end

        private

        def target(file) = File.join(directory.directory, file)

        def consider(software)
          entries = []
          reasons = []
          selection.consider(software).each do |reason, item|
            reason, entry = entry_for(item) if item
            reason ? reasons << reason : entries << entry
          end
          [ entries, reasons ]
        end

        def entry_for(item)
          reason, file, folder = @layout.name_for(item)
          return [ reason ] if reason

          software = item.software
          entry = Entry.new(file: file, kind: item.kind, version: item.release.version, size: item.size, title: software.title,
                            author: software.author, description: software.desc, category: software.category,
                            year: item.release.created_at&.year, source: item.source, software: software, folder: folder)
          add_preview(entry)
          [ nil, entry ]
        end

        def add_preview(entry)
          return unless @layout.previews?

          image = (entry.software.software_images.detect(&:is_default?) || entry.software.software_images.first)&.image
          path = image.respond_to?(:file_path) ? image.file_path.to_s : ""
          return unless File.file?(path)

          entry.preview = directory.preview_name_for(entry.file)
          entry.preview_source = path
        end

        def place_preview(entry, rewritten)
          preview = target(entry.preview)
          return if !rewritten && File.file?(preview) && File.mtime(entry.preview_source) <= File.mtime(preview)

          picture = directory.preview_renderer.new(entry.preview_source).render
          WarpEngine::Files.atomic(preview) { |temporary| File.binwrite(temporary, picture) }
        rescue StandardError => e
          Rails.logger.error("[WarpEngine::Feeds::Directory] preview of #{entry.file}: #{e.class}: #{e.message}")
          entry.preview = nil unless File.file?(preview)
        end

        def stale?(entry, previous)
          return true unless previous && previous[:crc32].present?
          return true unless previous[:version] == entry.version && previous[:size] == entry.size

          placed = target(entry.file)
          return true unless @layout.placed?(entry, placed)

          File.mtime(entry.source) > File.mtime(placed)
        end

        def with_lock
          FileUtils.mkdir_p(Dir.tmpdir)
          lock_path = File.join(Dir.tmpdir, "warp_engine-directory-#{directory.path.tr('/', '_')}.lock")
          File.open(lock_path, File::RDWR | File::CREAT) do |lock|
            lock.flock(File::LOCK_EX)
            yield
          end
        end
      end
    end
  end
end
