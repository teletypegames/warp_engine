module WarpEngine
  module SoftwareResponseBuilder
    private

    def build_response(software, releases, download_counts, subject: nil)
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
        download_counts: download_counts,
        access:          access_for(software, subject)
      )
    end

    # Always present, even under the open policy: a client should never have to tell
    # "this catalog says nothing about access" from "this title is not gated". One of
    # those is a question and the other is an answer.
    def access_for(software, subject)
      WarpEngine.access_policy.access_for(software: software, subject: subject)
    rescue StandardError => e
      # A policy that raises must not take the catalog down with it. The open answer is
      # wrong here, so the closed one is what a broken policy gets: a title nobody can
      # download is recoverable, a paid title handed out for free is not.
      Rails.logger.error("[WarpEngine::AccessPolicy] #{e.class}: #{e.message}")
      WarpEngine::Access.new(gated: true, entitled: false)
    end

    # The titles this subject may see. A policy that raises empties the catalog rather
    # than leaking it — the safe direction — but it is still a bug, so it is logged.
    def visible_scope(subject)
      WarpEngine.access_policy.visible_software_scope(subject: subject)
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::AccessPolicy] #{e.class}: #{e.message}")
      WarpEngine::Software.none
    end

    # Egyetlen csoportosított lekérdezés release-enkénti letöltésszámokhoz (N+1 helyett).
    def download_counts_for(release_ids)
      return {} if release_ids.empty?
      WarpEngine::Download.where(release_id: release_ids).group(:release_id).count
    end
  end
end
