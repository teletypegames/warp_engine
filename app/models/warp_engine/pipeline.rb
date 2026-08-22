module WarpEngine
  class Pipeline < ApplicationRecord
    self.table_name = "pipelines"

    UNKNOWN_PLATFORM = "unknown".freeze

    belongs_to :software, class_name: "WarpEngine::Software", optional: true

    attr_reader :software_taken_from

    default_scope { where(deleted_at: nil) }

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

    def remote_repo_id
      woodpecker_repo_id
    end

    def remote_repo_id=(value)
      self.woodpecker_repo_id = value
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
