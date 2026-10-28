module WarpEngine
  # A CI repository the engine tracks (table +pipelines+), mirrored from the
  # CI server by WarpEngine::PipelineSyncService. Identified by the CI's
  # repository id (+woodpecker_repo_id+, also #remote_repo_id), with the
  # repository owner and name, its +platform+ (a WarpEngine::Platform name or
  # UNKNOWN_PLATFORM), whether it is +active+, and the last run's status and
  # time. It may be linked to the WarpEngine::Software it builds; a software
  # belongs to one pipeline at most, so linking it takes it from the others.
  # Scopes: +active+ (kept and active) and +by_remote_repo_id+. Soft-deletable.
  class Pipeline < ApplicationRecord
    self.table_name = "pipelines"

    # Platform value of a repository whose platform could not be determined.
    UNKNOWN_PLATFORM = "unknown".freeze

    include SoftDeletable

    belongs_to :software, class_name: "WarpEngine::Software", optional: true

    # Full names of the pipelines the last save took the software from; empty
    # or +nil+ when it took none.
    attr_reader :software_taken_from

    before_save :claim_software_from_other_pipelines, if: :will_save_change_to_software_id?

    validates :woodpecker_repo_id, presence: true, uniqueness: true
    validates :repo_owner, presence: true
    validates :repo_name, presence: true
    validates :platform, presence: true,
              inclusion: { in: ->(_) { WarpEngine::Platform.names + [ UNKNOWN_PLATFORM ] } }

    scope :active, -> { kept.where(active: true) }

    scope :by_remote_repo_id, ->(id) { where(woodpecker_repo_id: id) }

    # Returns <tt>owner/name</tt> of the repository.
    def full_name
      "#{repo_owner}/#{repo_name}"
    end

    # Returns the CI's repository id.
    def remote_repo_id
      woodpecker_repo_id
    end

    # Sets the CI's repository id.
    def remote_repo_id=(value)
      self.woodpecker_repo_id = value
    end

    # Returns the pipeline of the CI repository +id+, or a new unsaved one.
    def self.find_or_initialize_by_remote_repo_id(id)
      find_or_initialize_by(woodpecker_repo_id: id)
    end

    private

    def claim_software_from_other_pipelines
      return if software_id.blank?

      others = Pipeline.where(software_id: software_id).where.not(id: id)
      @software_taken_from = others.map(&:full_name)
      return if @software_taken_from.empty?

      Rails.logger.info(
        "[WarpEngine::Pipeline] #{full_name} took software #{software_id} from " \
        "#{@software_taken_from.join(', ')}"
      )
      others.update_all(software_id: nil, updated_at: Time.current)
    end

    ActiveSupport.run_load_hooks(:warp_engine_pipeline, self)
  end
end
