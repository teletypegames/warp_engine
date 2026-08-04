module WarpEngine
  class PlatformLink < ApplicationRecord
    self.table_name = "platform_links"

    SUPPORTED_PLATFORMS = %w[tic80 ebitengine love c64 godot bevy phaser].freeze

    validates :name, presence: true
    validates :url, presence: true
    validates :platform, presence: true, inclusion: { in: SUPPORTED_PLATFORMS }

    default_scope { where(deleted_at: nil).order(:position) }

    def self.ransackable_attributes(auth_object = nil)
      %w[created_at deleted_at id name platform position updated_at url]
    end

    def self.ransackable_associations(auth_object = nil)
      []
    end

    def self.for_platform(platform)
      where(platform: platform).to_a
    end

    ActiveSupport.run_load_hooks(:warp_engine_platform_link, self)
  end
end
