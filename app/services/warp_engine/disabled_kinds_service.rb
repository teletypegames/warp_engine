module WarpEngine
  # Removes what a software turned off (WarpEngine::Software#disabled_kinds)
  # from the releases it published before: the release assets of the disabled
  # kinds are soft-deleted and their files (a folder for an unpacked kind)
  # removed from the file container. WarpEngine::PublishService runs it for the
  # software it publishes; <tt>rake warp_engine:releases:purge_disabled</tt>
  # runs it for every software.
  class DisabledKindsService
    # What a purge did, or would do in a dry run: +lines+ (one per asset) and
    # +count+.
    Report = ::Data.define(:lines, :count)

    # Purges the assets of the disabled kinds of +softwares+ (the kept
    # WarpEngine::Software records that disable an asset kind when +nil+).
    # With +dry_run+ nothing changes and the Report only lists them. Returns
    # a Report.
    def purge(softwares: nil, dry_run: false)
      lines = []
      Array(softwares || disabling).each do |software|
        assets_of(software).each do |asset|
          lines << "#{software.name} #{asset.release.version}: remove #{asset.kind} #{asset.path}"
          remove(asset) unless dry_run
        end
      end
      Report.new(lines, lines.size)
    end

    private

    def disabling
      WarpEngine::Software.kept.where.not(disabled_kinds: nil).select { |software| (software.disabled_kinds & WarpEngine::AssetKinds.names).any? }
    end

    def assets_of(software)
      kinds = software.disabled_kinds & WarpEngine::AssetKinds.names
      return [] if kinds.empty?

      WarpEngine::ReleaseAsset.kept.joins(:release).merge(WarpEngine::Release.kept)
                              .where(releases: { software_id: software.id }, kind: kinds).includes(:release).to_a
    end

    def remove(asset)
      asset.soft_delete!
      path = asset.path.to_s
      FileUtils.rm_rf(path) if path.start_with?(container) && path != container
    end

    def container = "#{WarpEngine.config.file_container_path.to_s.chomp('/')}/"
  end
end
