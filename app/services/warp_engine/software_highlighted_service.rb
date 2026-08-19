module WarpEngine
  class SoftwareHighlightedService
    include SoftwareResponseBuilder

    def index(subject: nil)
      software = visible_scope(subject).includes(:external_links, :software_images)
                         .where(highlighted: true)
                         .order(id: :desc)
                         .first
      return nil unless software

      releases = WarpEngine::Release.includes(:release_assets).where(software_id: software.id).to_a
      build_response(software, releases, download_counts_for(releases.map(&:id)), subject: subject)
    end
  end
end
