module WarpEngine
  class Pipeline < ApplicationRecord
    self.table_name = "pipelines"

    # Repos synced from Woodpecker without a matching Software land here
    # until a platform is assigned by hand.
    UNKNOWN_PLATFORM = "unknown".freeze

    belongs_to :software, class_name: "WarpEngine::Software", optional: true

    # Pipelines this record took the software from during the last save, by full name.
    # The admin says so out loud: a silent reassignment is what made the old behaviour
    # confusing in the first place.
    attr_reader :software_taken_from

    default_scope { where(deleted_at: nil) }

    # One pipeline per software, and the newest assignment wins.
    #
    # `Software#pipeline` is a `has_one`, so two pipelines pointing at the same software
    # is not an error — it is worse than one: the software keeps showing whichever row
    # comes first, and assigning it elsewhere looks like it did nothing. Rather than
    # refusing the assignment, the link moves: whoever held that software lets go of it.
    #
    # Deliberately a callback and not a unique index. Rows here are soft-deleted, and a
    # unique index counts deleted rows too, so a pipeline someone removed last year would
    # block the software from ever being linked again.
    before_save :claim_software_from_other_pipelines, if: :will_save_change_to_software_id?

    validates :woodpecker_repo_id, presence: true, uniqueness: true
    validates :repo_owner, presence: true
    validates :repo_name, presence: true
    validates :platform, presence: true,
              inclusion: { in: WarpEngine::PlatformLink::SUPPORTED_PLATFORMS + [ UNKNOWN_PLATFORM ] }

    scope :active, -> { where(active: true) }

    def full_name
      "#{repo_owner}/#{repo_name}"
    end

    def self.ransackable_attributes(auth_object = nil)
      %w[active created_at deleted_at id last_pipeline_at last_pipeline_status
         platform repo_name repo_owner software_id woodpecker_repo_id]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[software]
    end

    private

    def claim_software_from_other_pipelines
      return if software_id.blank?

      others = Pipeline.where(software_id: software_id).where.not(id: id)
      @software_taken_from = others.map(&:full_name)
      others.update_all(software_id: nil, updated_at: Time.current)
    end

    ActiveSupport.run_load_hooks(:warp_engine_pipeline, self)
  end
end
