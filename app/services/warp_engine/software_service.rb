module WarpEngine
  class SoftwareService
    include SoftwareResponseBuilder

    # `subject` is whoever the request authenticated as, or nil. It decides two things:
    # which titles are listed at all (the policy's scope) and what each one's `access`
    # block says about entitlement.
    def index(owner_id: nil, subject: nil)
      softwares = visible_scope(subject)
                  .includes(releases: [ :release_assets ])
                  .includes(:external_links, :software_images)
      softwares = softwares.where(owner_id: owner_id) if owner_id.present?
      counts = download_counts_for(softwares.flat_map { |sw| sw.releases.map(&:id) })
      { softwares: softwares.map { |sw| build_response(sw, sw.releases.to_a, counts, subject: subject) } }
    end
  end
end
