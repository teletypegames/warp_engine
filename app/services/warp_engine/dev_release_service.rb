module WarpEngine
  # Keeps the development builds (WarpEngine::Channels::DEV) from piling up:
  # of a software's builds of one branch only the newest stays, and none stays
  # once it has not been updated for the given number of days, except on the
  # kept branches. A pruned build
  # is soft-deleted with its assets, and its folder in the file container is
  # removed. Stable and beta releases are never touched.
  class DevReleaseService
    # What #prune did (or would do): one +line+ per build and the +count+.
    Report = ::Data.define(:lines, :count)

    # Prunes the development builds.
    #
    # [ttl_days]      a build not updated for this many days goes (default
    #                 WarpEngine::Configuration#dev_release_ttl_days)
    # [keep_branches] branches whose newest build stays whatever its age
    #                 (default WarpEngine::Configuration#dev_release_keep_branches;
    #                 slashes count as dashes)
    # [dry_run]       only report (default +true+)
    # [now]           the time the age is measured from
    #
    # Returns a Report.
    def prune(ttl_days: WarpEngine.config.dev_release_ttl_days, keep_branches: WarpEngine.config.dev_release_keep_branches,
              dry_run: true, now: Time.current)
      cutoff = now - ttl_days.to_i.days
      @kept = Array(keep_branches).map { |branch| branch.to_s.tr("/", "-") }
      doomed = WarpEngine::Release.kept.where(channel: WarpEngine::Channels::DEV).includes(:software, :release_assets)
                                  .group_by { |release| [ release.software_id, release.branch || release.version ] }
                                  .flat_map { |_, builds| doomed_of(builds, cutoff) }
      lines = doomed.map { |release, reason| "#{release.software&.name} #{release.version}: #{reason}" }
      doomed.each { |release, _| remove(release) } unless dry_run
      Report.new(lines, doomed.size)
    end

    private

    def doomed_of(builds, cutoff)
      newest, *older = builds.sort_by { |release| [ release.updated_at || Time.at(0), release.id ] }.reverse
      older.map { |release| [ release, "superseded by #{newest.version}" ] } +
        (stale?(newest, cutoff) ? [ [ newest, "not updated since #{newest.updated_at.to_date}" ] ] : [])
    end

    def stale?(release, cutoff)
      release.updated_at.present? && release.updated_at < cutoff && @kept.exclude?(release.branch)
    end

    def remove(release)
      ActiveRecord::Base.transaction do
        release.release_assets.each(&:soft_delete!)
        release.soft_delete!
      end
      return if release.software&.name.blank? || release.version.blank?

      FileUtils.rm_rf(WarpEngine::ReleaseLayout.absolute_directory(release.software.name, release.version))
    end
  end
end
