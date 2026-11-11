require "zlib"
require "fileutils"
require "json"

module WarpEngine
  # Builds one shelf (a WarpEngine::Shelves shelf): a folder of the file
  # container that holds the latest build of every listed title of a platform
  # under a fixed name, with an <tt>INDEX.TXT</tt> listing them. A +flat+ shelf
  # holds one file a title, a +folders+ shelf one folder a title and kind. A
  # flat shelf with a +preview+ also holds a picture of each title that has an
  # image, made by its WarpEngine::ShelfPreview renderer.
  class ShelfService
    # The first line of the index: the format version and the field names.
    # Version 2 added the last two fields, so a version 1 reader that stops
    # after the description still reads the rest of the line right.
    HEADER = "#SHELF 2 file|version|size|crc32|title|author|description|category|preview".freeze
    # The longest index line, in bytes; the description is cut to fit.
    LINE_LIMIT = 255
    # The read size, in bytes, when copying a file and computing its CRC32.
    CHUNK = 64 * 1024
    # The program description file written into each folder of a +folders+ shelf.
    INFO_FILE = "INFO.INI".freeze
    # The file list (<tt>crc32 size path</tt> per file) written into each folder
    # of a +folders+ shelf.
    MANIFEST_FILE = "FILES.LST".freeze

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

    # A software left off the shelf, with the +reason+.
    Skip = Struct.new(:software, :reason, keyword_init: true) do
      # Returns <tt>"name: reason"</tt>.
      def to_s = "#{software.name}: #{reason}"
    end

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

    # The WarpEngine::Shelves shelf being built.
    attr_reader :shelf

    # [shelf] the WarpEngine::Shelves shelf to build
    def initialize(shelf)
      @shelf = shelf
    end

    # Decides what the shelf holds, without touching the disk: for every kept,
    # ungated software of the platform with a listed status, the latest release
    # that has each kind of the shelf. A name already taken (by an older
    # software) skips the newer one.
    #
    # Returns <tt>[entries, skipped]</tt>: the Entry list sorted by title, and the
    # Skip list.
    def plan
      entries = []
      skipped = []
      taken = {}

      candidates.each do |software|
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
    # copies (or unpacks) the entries whose version, size or source changed,
    # renders the previews that are missing or older than their entry or image
    # (an image that cannot be rendered leaves the entry without a preview and
    # is logged), replaces the index when its text changes, then removes the
    # files (or, on a +folders+ shelf, the formerly listed folders) that left
    # the shelf. Entries not rewritten keep the CRC32 of the previous index.
    #
    # [dry_run] when +true+, only computes the Result and writes nothing
    #
    # Returns a Result. Raises ArgumentError when a folder zip holds an unsafe path.
    def sync!(dry_run: false)
      entries, skipped = plan
      with_lock do
        previous = read_index
        written = entries.select { |entry| stale?(entry, previous[entry.file]) }
        (entries - written).each { |entry| entry.crc32 = previous.dig(entry.file, :crc32) }
        removed = removable(previous) - entries.map(&:file) - entries.filter_map(&:preview)

        unless dry_run
          FileUtils.mkdir_p(shelf.directory)
          written.each { |entry| place(entry) }
          entries.each { |entry| place_preview(entry, written.include?(entry)) if entry.preview }
        end

        index = render(entries)
        index_changed = index != current_index_text

        unless dry_run
          replace_index(index) if index_changed
          removed.each { |file| FileUtils.rm_rf(File.join(shelf.directory, file)) }
        end

        Result.new(shelf: shelf, entries: entries, skipped: skipped, written: written,
                   removed: removed, index_changed: index_changed)
      end
    end

    private

    def candidates
      statuses = shelf.listed_statuses
      return WarpEngine::Software.none if statuses.empty?

      WarpEngine.access_policy.visible_software_scope(subject: nil)
                .where(platform: shelf.platform, status: statuses)
                .includes({ releases: :release_assets }, { software_images: :image })
                .order(:created_at, :id)
    end

    # Returns <tt>[entries, reasons]</tt> for +software+: one Entry per shelf kind
    # it can supply, and the reason for each kind it cannot.
    def consider(software)
      return [ [], [ "gated" ] ] if WarpEngine.access_policy.access_for(software: software, subject: nil).gated

      entries = []
      reasons = []
      shelf.kinds.each do |kind|
        reason, entry = consider_kind(software, kind)
        reason ? reasons << reason : entries << entry
      end
      [ entries, reasons ]
    end

    def consider_kind(software, kind)
      release, source = latest_with_asset(software, kind)
      return [ "no #{kind} asset in any release" ] if release.nil?

      folder = nil
      if shelf.folders?
        folder = folder_for(software, release, source, kind)
        return [ "no #{kind} folder in the metadata of #{release.version}" ] if folder.nil?
        return [ "#{folder[:folder].inspect} is not a usable folder name" ] unless shelf.folder_name_valid?(folder[:folder])

        file = folder[:folder]
      else
        file = shelf.file_name_for(software)
        return [ "no usable shelf name" ] if file.nil?
      end

      entry = Entry.new(file: file, kind: kind, version: release.version, size: File.size(source), title: software.title,
                        author: software.author, description: software.desc, category: software.category, source: source,
                        software: software, folder: folder)
      add_preview(entry)
      [ nil, entry ]
    end

    def add_preview(entry)
      return unless shelf.preview && !shelf.folders?

      image = (entry.software.software_images.detect(&:is_default?) || entry.software.software_images.first)&.image
      path = image.respond_to?(:file_path) ? image.file_path.to_s : ""
      return unless File.file?(path)

      entry.preview = shelf.preview_name_for(entry.file)
      entry.preview_source = path
    end

    # Writes the preview of +entry+ through a temporary file when it is
    # missing, its title was +rewritten+, or its image is newer; drops the
    # preview from the entry when the image cannot be rendered.
    def place_preview(entry, rewritten)
      target = File.join(shelf.directory, entry.preview)
      return if !rewritten && File.file?(target) && File.mtime(entry.preview_source) <= File.mtime(target)

      temporary = "#{target}.NEW"
      File.binwrite(temporary, shelf.preview_renderer.new(entry.preview_source).render)
      File.rename(temporary, target)
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::ShelfService] preview of #{entry.file}: #{e.class}: #{e.message}")
      FileUtils.rm_f(temporary) if temporary
      entry.preview = nil unless File.file?(target)
    end

    def latest_with_asset(software, kind)
      sources = {}
      software.releases.each do |release|
        asset = release.release_assets.find { |candidate| candidate.kind == kind }
        path = asset && absolute(asset.path)
        sources[release] = path if path && File.file?(path)
      end
      release = WarpEngine::Release.latest_non_dev(sources.keys)
      release ? [ release, sources[release] ] : nil
    end

    def folder_for(software, release, source, kind)
      metadata_path = File.join(File.dirname(source), "#{software.name}-#{release.version}.metadata.json")
      return nil unless File.file?(metadata_path)

      metadata = JSON.parse(File.read(metadata_path))
      spec = WarpEngine::Platform.find(shelf.platform)&.service_class&.shelf_folder(metadata, kind)
      spec&.to_h&.symbolize_keys
    rescue JSON::ParserError
      nil
    end

    def absolute(path)
      Pathname.new(path).absolute? ? path : File.join(WarpEngine.config.file_container_path, path)
    end

    # Whether +entry+ must be written again, comparing it with its line in the
    # previous index (+previous+) and the file on the shelf.
    def stale?(entry, previous)
      target = File.join(shelf.directory, entry.file)
      return true unless previous && previous[:crc32].present?
      return true unless shelf.folders? ? File.directory?(target) : File.file?(target)
      return true unless previous[:version] == entry.version && previous[:size] == entry.size
      return true unless shelf.folders? || File.size(target) == entry.size

      File.mtime(entry.source) > File.mtime(target)
    end

    def place(entry)
      shelf.folders? ? place_folder(entry) : place_file(entry)
    end

    # Copies the source of +entry+ to the shelf through a temporary file and sets
    # its CRC32.
    def place_file(entry)
      target = File.join(shelf.directory, entry.file)
      temporary = "#{target}.NEW"
      crc = 0
      File.open(entry.source, "rb") do |input|
        File.open(temporary, "wb") do |output|
          while (chunk = input.read(CHUNK))
            crc = Zlib.crc32(chunk, crc)
            output.write(chunk)
          end
        end
      end
      File.rename(temporary, target)
      entry.crc32 = format("%08x", crc)
    ensure
      FileUtils.rm_f(temporary) if temporary && File.exist?(temporary)
    end

    # Builds the folder of +entry+ next to the old one (unpacked files,
    # INFO_FILE, MANIFEST_FILE), swaps it in and sets the CRC32 of the source zip.
    def place_folder(entry)
      target = File.join(shelf.directory, entry.file)
      staging = "#{target}.NEW"
      retired = "#{target}.OLD"
      FileUtils.rm_rf([ staging, retired ])
      FileUtils.mkdir_p(staging)

      unpack_folder(entry, staging)
      File.binwrite(File.join(staging, INFO_FILE), info_text(entry))
      File.binwrite(File.join(staging, MANIFEST_FILE), manifest_text(staging))
      FileUtils.chmod_R("a+rX", staging)

      File.rename(target, retired) if File.exist?(target)
      File.rename(staging, target)
      FileUtils.rm_rf(retired)
      entry.crc32 = format("%08x", file_crc(entry.source))
    ensure
      FileUtils.rm_rf(staging) if staging && File.exist?(staging)
    end

    # Unpacks the files under the entry's folder in the source zip into
    # +staging+, leaving out its +settings+ files and the generated files. Raises
    # ArgumentError on an unsafe path.
    def unpack_folder(entry, staging)
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
      [ "[program]",
        "name=#{self.class.clean(folder[:name].presence || folder[:folder])}",
        "description=#{self.class.clean(folder[:description])}",
        "version=#{entry.version}",
        ("platform=#{self.class.clean(folder[:platform])}" if folder[:platform].present?) ].compact.map { |line| "#{line}\r\n" }.join
    end

    def manifest_text(staging)
      Dir.glob("**/*", base: staging).select { |relative| File.file?(File.join(staging, relative)) }
         .reject { |relative| relative == MANIFEST_FILE }.sort
         .map do |relative|
           path = File.join(staging, relative)
           "#{format('%08x', file_crc(path))} #{File.size(path)} #{relative}\r\n"
         end.join
    end

    def file_crc(path)
      crc = 0
      File.open(path, "rb") { |input| (crc = Zlib.crc32(input.read(CHUNK), crc)) until input.eof? }
      crc
    end

    def render(entries)
      ([ HEADER ] + entries.map(&:line)).join("\n") + "\n"
    end

    def replace_index(text)
      target = File.join(shelf.directory, Shelves::INDEX_FILE)
      temporary = "#{target}.NEW"
      File.write(temporary, text)
      File.rename(temporary, target)
    end

    def current_index_text
      path = File.join(shelf.directory, Shelves::INDEX_FILE)
      File.file?(path) ? File.read(path) : nil
    end

    # Parses the current index into a Hash of file name => +version+, +size+ and +crc32+.
    def read_index
      text = current_index_text
      return {} if text.nil?

      text.each_line.with_object({}) do |line, index|
        next if line.start_with?("#")

        file, version, size, crc32 = line.chomp.split("|", 5)
        next if file.blank?

        index[file] = { version: version, size: size.to_i, crc32: crc32 }
      end
    end

    def removable(previous)
      return previous.keys.select { |name| File.directory?(File.join(shelf.directory, name)) } if shelf.folders?

      present_files
    end

    def present_files
      return [] unless File.directory?(shelf.directory)

      Dir.children(shelf.directory).select { |name| File.file?(File.join(shelf.directory, name)) } - [ Shelves::INDEX_FILE ]
    end

    # Yields while holding an exclusive lock file for this shelf in the temporary directory.
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
