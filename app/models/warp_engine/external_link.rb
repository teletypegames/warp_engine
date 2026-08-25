module WarpEngine
  class ExternalLink < ApplicationRecord
    self.table_name = "external_links"

    include SoftDeletable

    belongs_to :software

    validates :label, presence: true
    validates :url, presence: true

    ActiveSupport.run_load_hooks(:warp_engine_external_link, self)
  end
end
