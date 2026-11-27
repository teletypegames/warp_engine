module WarpEngine
  # One file of a release: its +kind+ (one of KINDS, unique within the
  # release) and the absolute +path+ of the file in the file container.
  # Soft-deletable; saving or deleting one refreshes the feeds (directories) of the
  # software's platform.
  class ReleaseAsset < ApplicationRecord
    # Every asset kind, in catalog order (WarpEngine::AssetKinds.names).
    KINDS = WarpEngine::AssetKinds.names.freeze

    include SoftDeletable
    include FeedRefreshing

    belongs_to :release

    enum :kind, KINDS.index_by(&:itself)

    validates :path, presence: true
    validates :kind, uniqueness: { scope: :release_id }

    # Sets the kind, an old kind name read as its new one
    # (WarpEngine::AssetKinds.canonical).
    def kind=(value)
      super(value.nil? ? nil : WarpEngine::AssetKinds.canonical(value))
    end

    # Returns the platform of the release's software, whose feeds to refresh.
    def feed_platform = release&.software&.platform

    # Finds the asset of the file at +relative+, a path relative to the file
    # container: by its exact absolute path, else by the first path ending in
    # it. Returns the WarpEngine::ReleaseAsset or +nil+.
    def self.for_relative_path(relative)
      absolute = File.join(WarpEngine.config.file_container_path, relative.to_s)
      find_by(path: absolute) || where("path LIKE ?", "%/#{sanitize_sql_like(relative.to_s)}").first
    end

    ActiveSupport.run_load_hooks(:warp_engine_release_asset, self)
  end
end
