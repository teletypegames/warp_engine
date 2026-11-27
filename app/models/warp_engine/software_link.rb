module WarpEngine
  # A labelled link of a software to a page somewhere else (table
  # +software_links+). Needs a +label+ and a +url+. Soft-deletable. The git
  # repository a software is built from is not a link but its
  # WarpEngine::SoftwareSource.
  class SoftwareLink < ApplicationRecord
    self.table_name = "software_links"

    include SoftDeletable

    belongs_to :software

    validates :label, presence: true
    validates :url, presence: true

    ActiveSupport.run_load_hooks(:warp_engine_software_link, self)
  end
end
