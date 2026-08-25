module WarpEngine
  class ReleaseAsset < ApplicationRecord
    KINDS = %w[cartridge source html docs
               win_x86 win_x64 linux_x86 linux_x64 linux_arm64
               mac_x64 mac_arm64 mac_universal].freeze

    include SoftDeletable

    belongs_to :release

    enum :kind, KINDS.index_by(&:itself)

    validates :path, presence: true
    validates :kind, uniqueness: { scope: :release_id }

    def self.for_relative_path(relative)
      absolute = File.join(WarpEngine.config.file_container_path, relative.to_s)
      find_by(path: absolute) || where("path LIKE ?", "%/#{sanitize_sql_like(relative.to_s)}").first
    end

    ActiveSupport.run_load_hooks(:warp_engine_release_asset, self)
  end
end
