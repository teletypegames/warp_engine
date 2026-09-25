module WarpEngine
  class DownloadStatsService
    def summary(now: Time.current)
      {
        total: Download.count,
        today: Download.where(created_at: now.beginning_of_day..).count,
        week:  Download.where(created_at: 1.week.ago(now)..).count,
        month: Download.where(created_at: 1.month.ago(now)..).count
      }
    end

    def top_files(limit: 10)
      by_file(Download.all).first(limit)
    end

    def top_softwares(limit: 5)
      Download.joins(release: :software)
              .group("softwares.id", "softwares.name", "softwares.title")
              .order(Arel.sql("COUNT(*) DESC"))
              .limit(limit)
              .count
              .map { |(id, name, title), count| { software_id: id, name: name, title: title, downloads: count } }
    end

    def for_release(release)
      by_file(Download.where(release_id: release.id))
    end

    def for_software(software)
      releases = software.releases.to_a
      {
        total:    Download.joins(:release).where(releases: { software_id: software.id }).count,
        releases: releases.map do |release|
          files = for_release(release)
          { release_id: release.id, version: release.version, downloads: files.sum { |f| f[:downloads] }, files: files }
        end
      }
    end

    private

    def by_file(scope)
      scope.group(:file_path)
           .order(Arel.sql("COUNT(*) DESC"))
           .pluck(:file_path, Arel.sql("COUNT(*)"), Arel.sql("MAX(created_at)"))
           .map { |path, count, last| { file_path: path, downloads: count, last_download_at: last } }
    end
  end
end
