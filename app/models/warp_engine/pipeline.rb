module WarpEngine
  class Pipeline < ApplicationRecord
    self.table_name = "pipelines"

    # Repos synced from Woodpecker without a matching Software land here
    # until a platform is assigned by hand.
    UNKNOWN_PLATFORM = "unknown".freeze

    belongs_to :software, class_name: "WarpEngine::Software", optional: true

    default_scope { where(deleted_at: nil) }

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

    ActiveSupport.run_load_hooks(:warp_engine_pipeline, self)
  end
end
