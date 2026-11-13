require "fileutils"

module WarpEngine
  # Builds one shelf (a WarpEngine::Outlets::Shelf::Definition): a folder of the file
  # container that holds the latest build of every listed title of a platform
  # under a fixed name, with an <tt>INDEX.TXT</tt> listing them. A +flat+ shelf
  # holds one file a title, a +folders+ shelf one folder a title and kind. A
  # flat shelf with a +preview+ also holds a picture of each title that has an
  # image, made by its WarpEngine::ShelfPreview renderer.
  #
  # The service plans and orchestrates; the parts live beside the shelf
  # outlet: WarpEngine::Outlets::Shelf::IndexFile reads and writes the index,
  # WarpEngine::Outlets::Shelf::Layouts names and places the titles, and
  # WarpEngine::Files does the atomic writes and checksums.
  class ShelfService
    # The first line of the index (Outlets::Shelf::IndexFile::HEADER).
    HEADER = Outlets::Shelf::IndexFile::HEADER
    # The longest index line, in bytes; the description is cut to fit.
    LINE_LIMIT = 255
    # The program description file of a +folders+ shelf (Outlets::Shelf::Layouts::Folders::INFO_FILE).
    INFO_FILE = Outlets::Shelf::Layouts::Folders::INFO_FILE
    # The file list of a +folders+ shelf (Outlets::Shelf::Layouts::Folders::MANIFEST_FILE).
    MANIFEST_FILE = Outlets::Shelf::Layouts::Folders::MANIFEST_FILE

    # One title and kind on the shelf: the shelf +file+ (or folder) name, the
    # asset +kind+, +version+, +size+ and +crc32+ of the source, the +title+,
    # +author+, +description+ and +category+ of the software, the +source+
    # path, the +software+, on a +folders+ shelf the +folder+ spec, and the
    # +preview+ file name with the +preview_source+ image it is made from
    # (both +nil+ without a preview).
    Entry = Struct.new(:file, :kind, :version, :size, :crc32, :title, :author, :description, :source, :software,
                       :folder, :category, :preview, :preview_source, keyword_init: true) do
      # The index line of the entry:
      # <tt>file|version|size|crc32|title|author|description|category|preview</tt>,
      # cleaned with ShelfService.clean; the description is cut so that the
      # line fits in LINE_LIMIT bytes.
      def line
        fields = [ file, version, size, crc32, ShelfService.clean(title), ShelfService.clean(author) ]
        head = fields.join("|") + "|"
        tail = "|#{ShelfService.clean(category)}|#{preview}"
        head + ShelfService.clean(description)[0, [ LINE_LIMIT - head.bytesize - tail.bytesize, 0 ].max] + tail
      end
    end

    # A software left off the shelf, with the +reason+ (the
    # WarpEngine::Catalog::Offer skip).
    Skip = WarpEngine::Catalog::Offer::Skip

    # The outcome of #sync!: the +shelf+, the +entries+ on it, the +skipped+
    # softwares, the entries +written+, the file names +removed+, and whether the
    # index text changed.
    Result = Struct.new(:shelf, :entries, :skipped, :written, :removed, :index_changed, keyword_init: true) do
      # Whether the sync wrote a file, removed one or changed the index.
      def changed? = index_changed || written.any? || removed.any?
    end

    # Returns +text+ as printable ASCII for the index: transliterated, with
    # <tt>|</tt>, tabs and line breaks turned into spaces, other characters
    # dropped and spaces squeezed.
    def self.clean(text)
      I18n.transliterate(text.to_s).gsub(/[|\r\n\t]/, " ").gsub(/[^\x20-\x7E]/, "").squeeze(" ").strip
    end

    # The WarpEngine::Outlets::Shelf::Definition being built.
    attr_reader :shelf

    # [shelf] the WarpEngine::Outlets::Shelf::Definition to build
    def initialize(shelf)
      @shelf = shelf
      @layout = Outlets::Shelf::Layouts.for(shelf)
      @index = Outlets::Shelf::IndexFile.new(shelf.directory)
    end

    # Returns the WarpEngine::Catalog::Offer of the shelf: its platform, kinds
    # and listed statuses.
    def offer
      @offer ||= WarpEngine::Catalog::Offer.new(platforms: [ shelf.platform ], kinds: shelf.kinds, statuses: shelf.statuses)
    end

    # Decides what the shelf holds, without touching the disk: what #offer
    # offers, each item named for the shelf by its layout. A name already taken
    # (by an older software) skips the newer one.
    #
    # Returns <tt>[entries, skipped]</tt>: the Entry list sorted by title, and the
    # Skip list.
    def plan
      entries = []
      skipped = []
      taken = {}

      offer.candidates.each do |software|
        found, reasons = consider(software)
        skipped << Skip.new(software: software, reason: reasons.join("; ")) if found.empty?

        found.each do |entry|
          if taken.key?(entry.file)
            skipped << Skip.new(software: software, reason: "#{entry.file} is taken by #{taken[entry.file].name}")
          else
            taken[entry.file] = software
            entries << entry
          end
        end
      end

      [ entries.sort_by { |entry| [ entry.title.to_s.downcase, entry.file ] }, skipped ]
    end

    # Brings the shelf folder in line with #plan, under an exclusive file lock:
    # places (copies or unpacks) the entries whose version, size or source
    # changed, renders the previews that are missing or older than their entry
    # or image (an image that cannot be rendered leaves the entry without a
    # preview and is logged), replaces the index when its text changes, then
    # removes the files (or, on a +folders+ shelf, the formerly listed folders)
    # that left the shelf. Entries not rewritten keep the CRC32 of the previous
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
        removed = @layout.removable(shelf.directory, previous) - entries.map(&:file) - entries.filter_map(&:preview)

        index_changed = @index.changed?(entries)
        unless dry_run
          FileUtils.mkdir_p(shelf.directory)
          written.each { |entry| @layout.place(entry, target(entry.file)) }
          entries.each { |entry| place_preview(entry, written.include?(entry)) if entry.preview }
          index_changed = @index.write(entries)
          removed.each { |file| FileUtils.rm_rf(target(file)) }
        end

        Result.new(shelf: shelf, entries: entries, skipped: skipped, written: written,
                   removed: removed, index_changed: index_changed)
      end
    end

    private

    def target(file) = File.join(shelf.directory, file)

    def consider(software)
      entries = []
      reasons = []
      offer.consider(software).each do |reason, item|
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
                        source: item.source, software: software, folder: folder)
      add_preview(entry)
      [ nil, entry ]
    end

    def add_preview(entry)
      return unless @layout.previews?

      image = (entry.software.software_images.detect(&:is_default?) || entry.software.software_images.first)&.image
      path = image.respond_to?(:file_path) ? image.file_path.to_s : ""
      return unless File.file?(path)

      entry.preview = shelf.preview_name_for(entry.file)
      entry.preview_source = path
    end

    def place_preview(entry, rewritten)
      preview = target(entry.preview)
      return if !rewritten && File.file?(preview) && File.mtime(entry.preview_source) <= File.mtime(preview)

      picture = shelf.preview_renderer.new(entry.preview_source).render
      WarpEngine::Files.atomic(preview) { |temporary| File.binwrite(temporary, picture) }
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::ShelfService] preview of #{entry.file}: #{e.class}: #{e.message}")
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
      lock_path = File.join(Dir.tmpdir, "warp_engine-shelf-#{shelf.path.tr('/', '_')}.lock")
      File.open(lock_path, File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end
  end
end
