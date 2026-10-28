module WarpEngine
  # A link shown with every software of a platform (table +platform_links+),
  # e.g. where to get the emulator. Has a +name+, a +url+, a +platform+ and a
  # +position+ (scope +ordered+). Soft-deletable.
  class PlatformLink < ApplicationRecord
    self.table_name = "platform_links"

    # The built-in platforms (WarpEngine::Platform::BUILTIN).
    SUPPORTED_PLATFORMS = WarpEngine::Platform::BUILTIN

    include SoftDeletable

    validates :name, presence: true
    validates :url, presence: true
    validates :platform, presence: true, inclusion: { in: ->(_) { WarpEngine::Platform.names } }

    scope :ordered, -> { order(:position) }

    # Returns the kept links of +platform+ in position order, as an Array.
    def self.for_platform(platform)
      kept.ordered.where(platform: platform).to_a
    end

    ActiveSupport.run_load_hooks(:warp_engine_platform_link, self)
  end
end
