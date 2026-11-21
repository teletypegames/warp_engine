module WarpEngine
  # A fork of a software of this engine that lives on another engine and
  # announced itself (table +fork_links+): the +child_engine+ base URL and the
  # +child_name+ there, its +child_title+, and the moderation +status+ —
  # +pending+ until an administrator decides, +visible+ (listed by
  # <tt>GET /api/softwares/:name/forks</tt>), +hidden+, or +gone+ when the
  # recheck no longer finds it. +checked_at+ and +last_error+ record the
  # newest verification (WarpEngine::ForkService). Soft-deletable.
  class ForkLink < ApplicationRecord
    self.table_name = "fork_links"

    include SoftDeletable

    # The moderation statuses.
    STATUSES = %w[pending visible hidden gone].freeze

    belongs_to :software

    validates :child_engine, presence: true, length: { maximum: 255 }
    validates :child_name, presence: true, length: { maximum: 128 }
    validates :status, inclusion: { in: STATUSES }
    validates :child_name, uniqueness: { scope: %i[software_id child_engine] }

    scope :visible, -> { kept.where(status: "visible") }
    scope :pending, -> { kept.where(status: "pending") }

    ActiveSupport.run_load_hooks(:warp_engine_fork_link, self)
  end
end
