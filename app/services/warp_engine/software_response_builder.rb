module WarpEngine
  module SoftwareResponseBuilder
    private

    def build_response(software, releases, download_counts)
      sorted = releases.sort_by { |r| r.created_at || Time.at(0) }.reverse
      latest = sorted.reject { |r| r.version.to_s.start_with?("dev-") }.first
      # web-playable, ha az utolsó (stabil) release-nek van webes assetje
      web_playable = latest if latest&.release_assets&.any? { |a| a.kind == "html" }
      total_downloads = releases.sum { |r| download_counts.fetch(r.id, 0) }

      SoftwareDetailSerializer.render_as_hash(software,
        releases:        sorted,
        latest:          latest,
        web_playable:    web_playable,
        total_downloads: total_downloads,
        download_counts: download_counts
      )
    end

    # Egyetlen csoportosított lekérdezés release-enkénti letöltésszámokhoz (N+1 helyett).
    def download_counts_for(release_ids)
      return {} if release_ids.empty?
      WarpEngine::Download.where(release_id: release_ids).group(:release_id).count
    end
  end
end
