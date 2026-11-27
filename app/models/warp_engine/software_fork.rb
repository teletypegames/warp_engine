module WarpEngine
  # A fork of a software of this engine that lives on another engine and
  # announced itself (table +software_forks+): the +engine_url+ (the base
  # URL of that engine), the +name+ there, its +title+, and the moderation
  # +status+ —
  # +pending+ until an administrator decides, +visible+ (listed by
  # <tt>GET /api/softwares/:name/forks</tt>), +hidden+, or +gone+ when the
  # recheck no longer finds it. +checked_at+ and +last_error+ record the
  # newest verification (WarpEngine::ForkService). Soft-deletable.
  class SoftwareFork < ApplicationRecord
    self.table_name = "software_forks"

    include SoftDeletable

    # The moderation statuses.
    STATUSES = %w[pending visible hidden gone].freeze

    belongs_to :software

    validates :engine_url, presence: true, length: { maximum: 255 }
    validates :name, presence: true, length: { maximum: 128 }
    validates :status, inclusion: { in: STATUSES }
    validates :name, uniqueness: { scope: %i[software_id engine_url] }

    scope :visible, -> { kept.where(status: "visible") }
    scope :pending, -> { kept.where(status: "pending") }

    ActiveSupport.run_load_hooks(:warp_engine_software_fork, self)
  end
end
