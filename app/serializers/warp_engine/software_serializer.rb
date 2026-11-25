module WarpEngine
  # Catalog view of a WarpEngine::Software: id, timestamps (see
  # WarpEngine::TimestampFields), name, title, author, descriptions, license,
  # platform, status, category, owner id, highlighted flag, +disabledKinds+
  # (WarpEngine::Software#disabled_kinds: <tt>stores</tt> among them keeps
  # the store engines from offering it), external links,
  # the platform's links, the default image URL and the image gallery; and
  # for forking: +source+ (the source link with +url+, +ref+, +public+ and
  # +verifiedAt+, or +null+), +forksAllowed+ (WarpEngine::Software#forkable?),
  # +forkOf+ (the parent's +engine+, +name+, +version+, +repo+ and +local+, or
  # +null+) and +forksCount+ (WarpEngine::Current#fork_count).
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
    field :category

    field(:ownerId) { |sw| sw.owner_id }
    field(:highlighted)  { |sw| sw.highlighted ? true : false }
    field(:disabledKinds) { |sw| sw.disabled_kinds }
    field(:externalLinks) { |sw| ExternalLinkSerializer.render_as_hash(sw.external_links) }
    field(:source) { |sw|
      link = sw.source_link
      link && { url: link.url, ref: link.ref, public: link.public, verifiedAt: link.verified_at&.utc&.strftime(TS_FORMAT) }
    }
    field(:forksAllowed) { |sw| sw.forkable? }
    field(:forkOf) { |sw|
      sw.fork? ? { engine: sw.fork_of_engine, name: sw.fork_of_name, version: sw.fork_of_version, repo: sw.fork_of_repo,
                   local: WarpEngine::Forks.own?(sw.fork_of_engine) } : nil
    }
    field(:forksCount) { |sw| WarpEngine::Current.fork_count(sw) }
    field(:platformLinks) { |sw| PlatformLinkSerializer.render_as_hash(WarpEngine::PlatformLink.for_platform(sw.platform)) }
    field(:imageUrl) { |sw|
      si = sw.software_images.detect(&:is_default?) || sw.software_images.first
      si ? WarpEngine::Images.url_for(si.image_id) : nil
    }
    field(:images) { |sw|
      sw.software_images.map { |si|
        { url: WarpEngine::Images.url_for(si.image_id), isDefault: si.is_default?, position: si.position }
      }
    }
  end
end
