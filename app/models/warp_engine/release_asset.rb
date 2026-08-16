module WarpEngine
  class ReleaseAsset < ApplicationRecord
    KINDS = %w[cartridge source html docs
               win_x86 win_x64 linux_x86 linux_x64 linux_arm64
               mac_x64 mac_arm64 mac_universal].freeze

    belongs_to :release

    enum :kind, KINDS.index_by(&:itself)

    validates :path, presence: true
    validates :kind, uniqueness: { scope: :release_id }

    default_scope { where(deleted_at: nil) }

    def self.ransackable_attributes(auth_object = nil)
      %w[created_at deleted_at id kind path release_id updated_at]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[release]
    end

    ActiveSupport.run_load_hooks(:warp_engine_release_asset, self)
  end
end
