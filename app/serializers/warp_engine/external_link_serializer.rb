module WarpEngine
  # Catalog view of a WarpEngine::ExternalLink: id, timestamps (see
  # WarpEngine::TimestampFields), software id, label and URL.
  class ExternalLinkSerializer < Blueprinter::Base
    include TimestampFields

    field(:id)         { |el| el.id }
    field(:createdAt)  { |el| el.created_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:updatedAt)  { |el| el.updated_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:deletedAt)  { |el| el.deleted_at&.utc&.strftime(TS_FORMAT) }
    field(:softwareId) { |el| el.software_id }
    field :label
    field :url
  end
end
