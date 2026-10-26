module WarpEngine
  class PlatformLink < ApplicationRecord
    self.table_name = "platform_links"

    SUPPORTED_PLATFORMS = WarpEngine::Platform::BUILTIN

    include SoftDeletable

    validates :name, presence: true
    validates :url, presence: true
    validates :platform, presence: true, inclusion: { in: ->(_) { WarpEngine::Platform.names } }

    scope :ordered, -> { order(:position) }

    def self.for_platform(platform)
      kept.ordered.where(platform: platform).to_a
    end

    ActiveSupport.run_load_hooks(:warp_engine_platform_link, self)
  end
end
