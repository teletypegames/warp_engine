module WarpEngine
  class SoftwareHighlightedService
    include SoftwareResponseBuilder

    def index(subject: nil)
      software = visible_scope(subject)
        .includes(releases: :release_assets)
        .includes(:external_links, :software_images)
        .where(highlighted: true)
        .order(id: :desc)
        .first
      return nil unless software

      releases = software.releases.to_a
      build_response(software, releases, download_counts_for(releases.map(&:id)), subject: subject)
    end
  end
end
