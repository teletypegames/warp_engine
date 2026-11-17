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
    # An entry belongs to the release whose <tt>name-version</tt> it starts
    # with, or to the release of an asset in the root whose name it starts
    # the same way (a renamed software's files).
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

        name, version, new_name = WarpEngine::ReleaseLayout.legacy_parts(entry, owners)
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
    # there. A file a renamed software's release still names after the old
    # name is found by its asset record.
    def relocate(relative)
      entry, rest = relative.to_s.delete_prefix("/").split("/", 2)
      return nil if entry.blank?

      target = by_release(entry, rest) || by_asset(entry, rest)
      storage = WarpEngine.storage
      target && (storage.file?(target) || storage.directory?(target)) ? target : nil
    end

    private

    def root = Pathname.new(WarpEngine.config.file_container_path.to_s)

    def software_names = WarpEngine::Software.where.not(name: nil).pluck(:name)

    def owners
      @owners ||= WarpEngine::ReleaseLayout.owners(release_pairs(WarpEngine::Release.all), root_assets)
    end

    def release_pairs(scope) = scope.joins(:software).where.not(version: nil).pluck("softwares.name", :version)

    def root_assets
      prefix = "#{root.to_s.chomp('/')}/"
      WarpEngine::ReleaseAsset.where("path LIKE ?", "#{WarpEngine::ReleaseAsset.sanitize_sql_like(prefix)}%")
                              .includes(release: :software).each_with_object({}) do |asset, found|
        entry = asset.path.to_s.delete_prefix(prefix).chomp("/")
        next if entry.include?("/") || asset.release&.software&.name.blank? || asset.release.version.blank?

        found[entry] = [ asset.release.software.name, asset.release.version ]
      end
    end

    def by_release(entry, rest)
      return nil unless entry.include?("-")

      names = WarpEngine::Software.where.not(name: nil).pluck(:name).select { |name| entry.start_with?("#{name}-") }
      pairs = release_pairs(WarpEngine::Release.where(software_id: WarpEngine::Software.where(name: names).select(:id)))
      name, version, new_name = WarpEngine::ReleaseLayout.legacy_parts(entry, WarpEngine::ReleaseLayout.owners(pairs))
      name && File.join(*[ WarpEngine::ReleaseLayout.directory(name, version), new_name, rest ].compact_blank)
    end

    def by_asset(entry, rest)
      asset = WarpEngine::ReleaseAsset.where("path LIKE ?", "%/#{WarpEngine::ReleaseAsset.sanitize_sql_like(entry)}").first
      return nil if asset.nil?

      relative = asset.path.to_s.delete_prefix("#{root.to_s.chomp('/')}/")
      File.join(*[ relative, rest ].compact_blank)
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
