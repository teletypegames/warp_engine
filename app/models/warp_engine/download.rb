module WarpEngine
  class Download < ApplicationRecord
    belongs_to :release, optional: true

    validates :file_path, presence: true

    default_scope { where(deleted_at: nil) }

    def self.ransackable_attributes(auth_object = nil)
      %w[created_at deleted_at file_path id ip_address referer release_id updated_at user_agent]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[release]
    end

    ActiveSupport.run_load_hooks(:warp_engine_download, self)
  end
end
