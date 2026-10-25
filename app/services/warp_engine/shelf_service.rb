require "zlib"
require "fileutils"

module WarpEngine
  class ShelfService
    HEADER = "#SHELF 1 file|version|size|crc32|title|author|description".freeze
    LINE_LIMIT = 255
    CHUNK = 64 * 1024

    Entry = Struct.new(:file, :version, :size, :crc32, :title, :author, :description, :source, :software, keyword_init: true) do
      def line
        fields = [ file, version, size, crc32, ShelfService.clean(title), ShelfService.clean(author) ]
        head = fields.join("|") + "|"
        head + ShelfService.clean(description)[0, [ LINE_LIMIT - head.bytesize, 0 ].max]
      end
    end

    Skip = Struct.new(:software, :reason, keyword_init: true) do
      def to_s = "#{software.name}: #{reason}"
    end

    Result = Struct.new(:shelf, :entries, :skipped, :written, :removed, :index_changed, keyword_init: true) do
      def changed? = index_changed || written.any? || removed.any?
    end

    def self.clean(text)
      I18n.transliterate(text.to_s).gsub(/[|\r\n\t]/, " ").gsub(/[^\x20-\x7E]/, "").squeeze(" ").strip
    end

    attr_reader :shelf

    def initialize(shelf)
      @shelf = shelf
    end

    def plan
      entries = []
      skipped = []
      taken = {}

      candidates.each do |software|
        reason, entry = consider(software)
        if reason
          skipped << Skip.new(software: software, reason: reason)
        elsif taken.key?(entry.file)
          skipped << Skip.new(software: software, reason: "#{entry.file} is taken by #{taken[entry.file].name}")
        else
          taken[entry.file] = software
          entries << entry
        end
      end

      [ entries.sort_by { |entry| [ entry.title.to_s.downcase, entry.file ] }, skipped ]
    end

    def sync!(dry_run: false)
      entries, skipped = plan
      with_lock do
        previous = read_index
        written = entries.select { |entry| stale?(entry, previous[entry.file]) }
        (entries - written).each { |entry| entry.crc32 = previous.dig(entry.file, :crc32) }
        removed = present_files - entries.map(&:file)

        unless dry_run
          FileUtils.mkdir_p(shelf.directory)
          written.each { |entry| place(entry) }
        end

        index = render(entries)
        index_changed = index != current_index_text

        unless dry_run
          replace_index(index) if index_changed
          removed.each { |file| FileUtils.rm_f(File.join(shelf.directory, file)) }
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
                .includes(releases: :release_assets)
                .order(:created_at, :id)
    end

    def consider(software)
      return [ "gated" ] if WarpEngine.access_policy.access_for(software: software, subject: nil).gated

      file = shelf.file_name_for(software)
      return [ "no usable shelf name" ] if file.nil?

      release, source = latest_with_asset(software)
      return [ "no #{shelf.kind} asset in any release" ] if release.nil?

      [ nil, Entry.new(file: file, version: release.version, size: File.size(source), title: software.title,
                       author: software.author, description: software.desc, source: source, software: software) ]
    end

    def latest_with_asset(software)
      sources = {}
      software.releases.each do |release|
        asset = release.release_assets.find { |candidate| candidate.kind == shelf.kind }
        path = asset && absolute(asset.path)
        sources[release] = path if path && File.file?(path)
      end
      release = WarpEngine::Release.latest_non_dev(sources.keys)
      release ? [ release, sources[release] ] : nil
    end

    def absolute(path)
      Pathname.new(path).absolute? ? path : File.join(WarpEngine.config.file_container_path, path)
    end

    def stale?(entry, previous)
      target = File.join(shelf.directory, entry.file)
      return true unless previous && previous[:crc32].present? && File.file?(target)
      return true unless previous[:version] == entry.version && previous[:size] == entry.size
      return true unless File.size(target) == entry.size

      File.mtime(entry.source) > File.mtime(target)
    end

    def place(entry)
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

    def present_files
      return [] unless File.directory?(shelf.directory)

      Dir.children(shelf.directory).select { |name| File.file?(File.join(shelf.directory, name)) } - [ Shelves::INDEX_FILE ]
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
