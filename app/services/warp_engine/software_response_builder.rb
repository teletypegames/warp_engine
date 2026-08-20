module WarpEngine
  module SoftwareResponseBuilder
    private

    def build_response(software, releases, download_counts, subject: nil)
      sorted = releases.sort_by { |r| r.created_at || Time.at(0) }.reverse
      latest = sorted.reject { |r| r.version.to_s.start_with?("dev-") }.first

      web_playable = latest if latest&.release_assets&.any? { |a| a.kind == "html" }
      total_downloads = releases.sum { |r| download_counts.fetch(r.id, 0) }

      SoftwareDetailSerializer.render_as_hash(software,
        releases:        sorted,
        latest:          latest,
        web_playable:    web_playable,
        total_downloads: total_downloads,
        download_counts: download_counts,
        access:          access_for(software, subject)
      )
    end

    def access_for(software, subject)
      WarpEngine.access_policy.access_for(software: software, subject: subject)
    rescue StandardError => e

      Rails.logger.error("[WarpEngine::AccessPolicy] #{e.class}: #{e.message}")
      WarpEngine::Access.new(gated: true, entitled: false)
    end

    def visible_scope(subject)
      WarpEngine.access_policy.visible_software_scope(subject: subject)
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::AccessPolicy] #{e.class}: #{e.message}")
      WarpEngine::Software.none
    end

    def download_counts_for(release_ids)
      return {} if release_ids.empty?
      WarpEngine::Download.where(release_id: release_ids).group(:release_id).count
    end
  end
end
