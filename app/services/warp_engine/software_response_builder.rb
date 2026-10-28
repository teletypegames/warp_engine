module WarpEngine
  # Mixin of the catalog services: builds the catalog entry of a software and
  # reads through the access policy, falling back to the safe answer when the
  # policy raises.
  module SoftwareResponseBuilder
    private

    # Renders +software+ with WarpEngine::SoftwareDetailSerializer: its
    # +releases+ newest first, the latest non-dev release, the web playable
    # release (the latest, when it has an +html+ asset), the download totals from
    # +download_counts+ (release id => count) and the access of +subject+.
    # Returns a Hash.
    def build_response(software, releases, download_counts, subject: nil)
      sorted = releases.sort_by { |r| r.created_at || Time.at(0) }.reverse
      latest = Release.latest_non_dev(releases)

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

    # The WarpEngine::Access of +subject+ to +software+ from the access policy;
    # a gated, not entitled Access when the policy raises (the error is logged).
    def access_for(software, subject)
      WarpEngine.access_policy.access_for(software: software, subject: subject)
    rescue StandardError => e

      Rails.logger.error("[WarpEngine::AccessPolicy] #{e.class}: #{e.message}")
      WarpEngine::Access.new(gated: true, entitled: false)
    end

    # The softwares the access policy shows +subject+; an empty relation when
    # the policy raises (the error is logged).
    def visible_scope(subject)
      WarpEngine.access_policy.visible_software_scope(subject: subject)
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::AccessPolicy] #{e.class}: #{e.message}")
      WarpEngine::Software.none
    end

    # Returns a Hash of release id => count of kept downloads for +release_ids+.
    def download_counts_for(release_ids)
      return {} if release_ids.empty?
      WarpEngine::Download.kept.where(release_id: release_ids).group(:release_id).count
    end
  end
end
