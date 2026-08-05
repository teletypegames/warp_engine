module WarpEngine
  class SoftwareSerializer < Blueprinter::Base
    include TimestampFields

    field(:id)           { |sw| sw.id }
    field(:createdAt)    { |sw| sw.created_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:updatedAt)    { |sw| sw.updated_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:deletedAt)    { |sw| sw.deleted_at&.utc&.strftime(TS_FORMAT) }
    field :name
    field :title
    field :author
    field(:desc)         { |sw| sw.desc.to_s }
    field(:story)        { |sw| sw.story.to_s }
    field(:license)      { |sw| sw.license.to_s }
    field :platform
    field :status
    # Publikus owner-azonosító — az /api/software?owner_id= szűrőhöz.
    field(:ownerId) { |sw| sw.owner_id }
    field(:highlighted)  { |sw| sw.highlighted ? true : false }
    field(:externalLinks) { |sw| ExternalLinkSerializer.render_as_hash(sw.external_links) }
    field(:platformLinks) { |sw| PlatformLinkSerializer.render_as_hash(WarpEngine::PlatformLink.for_platform(sw.platform)) }
    field(:imageUrl) { |sw|
      si = sw.software_images.detect(&:is_default?) || sw.software_images.first
      si ? "/api/image/#{si.image_id}" : nil
    }
    field(:images) { |sw|
      sw.software_images.map { |si|
        { url: "/api/image/#{si.image_id}", isDefault: si.is_default?, position: si.position }
      }
    }
  end
end
