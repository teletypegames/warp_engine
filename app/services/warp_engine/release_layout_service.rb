require "fileutils"

module WarpEngine
  # Moves the file container from the flat layout before 3.4 to the folder of
  # every release (WarpEngine::ReleaseLayout) with #restructure, and finds
  # where an old flat path went with #relocate, so the old URLs still lead to
  # the file.
  class ReleaseLayoutService
    # What #restructure did (or would do): +lines+ to print, one per entry of
    # the root, and +count+, the entries moved (to be moved).
    Report = ::Data.define(:lines, :count)

    # Moves every root entry of the file container that belongs to a release
    # (deleted ones too) into that release's folder: a file keeps its name, an
    # unpacked folder gets its kind's (WarpEngine::ReleaseLayout.legacy_parts).
    # The paths of the WarpEngine::ReleaseAsset and WarpEngine::Download
    # records follow, then the outlets are refreshed. The reserved folders
    # (WarpEngine::ReleaseLayout.reserved), the software folders and the
    # hidden entries stay; an entry no release owns, or whose target exists,
    # is reported and left alone. Returns a Report.
    def restructure(dry_run: true)
      lines = []
      count = 0
      skipped = WarpEngine::ReleaseLayout.reserved + software_names
      root.children.sort.each do |path|
        entry = path.basename.to_s
        next if entry.start_with?(".") || skipped.include?(entry)

        name, version, new_name = WarpEngine::ReleaseLayout.legacy_parts(entry, releases)
        if name.nil?
          lines << "#{entry}: left, no release owns it"
          next
        end

        target = File.join(WarpEngine::ReleaseLayout.directory(name, version), new_name)
        if root.join(target).exist?
          lines << "#{entry}: left, #{target} exists"
          next
        end

        count += 1
        lines << "#{entry} -> #{target}"
        move(entry, target) unless dry_run
      end
      WarpEngine::Outlets.refresh if !dry_run && count.positive?
      Report.new(lines, count)
    end

    # Returns where the flat-layout path +relative+ (relative to the file
    # container, e.g. <tt>game-1.0.prg</tt> or <tt>game-1.0/index.html</tt>)
    # is now, or +nil+ when it names no release's file or the file is not
    # there.
    def relocate(relative)
      entry, rest = relative.to_s.delete_prefix("/").split("/", 2)
      return nil if entry.blank? || !entry.include?("-")

      name, version, new_name = WarpEngine::ReleaseLayout.legacy_parts(entry, releases_for(entry))
      return nil if name.nil?

      target = File.join(*[ WarpEngine::ReleaseLayout.directory(name, version), new_name, rest ].compact_blank)
      storage = WarpEngine.storage
      storage.file?(target) || storage.directory?(target) ? target : nil
    end

    private

    def root = Pathname.new(WarpEngine.config.file_container_path.to_s)

    def software_names = WarpEngine::Software.where.not(name: nil).pluck(:name)

    def releases
      @releases ||= WarpEngine::Release.joins(:software).where.not(version: nil).pluck("softwares.name", :version)
    end

    def releases_for(entry)
      names = WarpEngine::Software.where.not(name: nil).pluck(:name).select { |name| entry.start_with?("#{name}-") }
      WarpEngine::Release.joins(:software).where(softwares: { name: names }).where.not(version: nil)
                         .pluck("softwares.name", :version)
    end

    def move(entry, target)
      from = root.join(entry)
      to = root.join(target)
      FileUtils.mkdir_p(to.dirname)
      File.rename(from, to)
      begin
        ActiveRecord::Base.transaction { repoint(entry, target) }
      rescue StandardError
        File.rename(to, from)
        raise
      end
    end

    def repoint(entry, target)
      from = root.join(entry).to_s
      to = root.join(target).to_s
      WarpEngine::ReleaseAsset.where(path: [ from, "#{from}/" ]).update_all(path: to, updated_at: Time.current)
      WarpEngine::Download.where(file_path: entry).update_all(file_path: target)
      WarpEngine::Download.where("file_path LIKE ?", "#{WarpEngine::Download.sanitize_sql_like(entry)}/%")
                          .update_all([ "file_path = CONCAT(?, SUBSTRING(file_path, ?))", target, entry.length + 1 ])
    end
  end
end
