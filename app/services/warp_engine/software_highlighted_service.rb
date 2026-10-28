module WarpEngine
  # Finds the highlighted software of the catalog.
  class SoftwareHighlightedService
    include SoftwareResponseBuilder

    # Returns the catalog response of the newest highlighted software that the
    # access policy shows +subject+ (+nil+ for anonymous), built like a
    # WarpEngine::SoftwareDetailSerializer entry of the catalog, or +nil+ when
    # there is none.
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
