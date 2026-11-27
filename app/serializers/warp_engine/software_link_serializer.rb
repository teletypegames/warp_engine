module WarpEngine
  # Catalog view of a WarpEngine::SoftwareLink: id, timestamps (see
  # WarpEngine::TimestampFields), software id, label and URL.
  class SoftwareLinkSerializer < Blueprinter::Base
    include TimestampFields

    field(:id)         { |link| link.id }
    field(:createdAt)  { |link| link.created_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:updatedAt)  { |link| link.updated_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:deletedAt)  { |link| link.deleted_at&.utc&.strftime(TS_FORMAT) }
    field(:softwareId) { |link| link.software_id }
    field :label
    field :url
  end
end
