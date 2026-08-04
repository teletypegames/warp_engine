module WarpEngine
  class SoftwareService
    include SoftwareResponseBuilder

    def index
      softwares = WarpEngine::Software.includes(releases: [ :release_assets ]).includes(:external_links, :software_images).all
      counts = download_counts_for(softwares.flat_map { |sw| sw.releases.map(&:id) })
      { softwares: softwares.map { |sw| build_response(sw, sw.releases.to_a, counts) } }
    end
  end
end
