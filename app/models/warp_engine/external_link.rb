module WarpEngine
  # A labelled link of a software to somewhere else (table +external_links+),
  # e.g. its source repository. Needs a +label+ and a +url+. Soft-deletable.
  class ExternalLink < ApplicationRecord
    self.table_name = "external_links"

    include SoftDeletable

    belongs_to :software

    validates :label, presence: true
    validates :url, presence: true

    ActiveSupport.run_load_hooks(:warp_engine_external_link, self)
  end
end
