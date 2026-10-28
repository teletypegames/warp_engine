module WarpEngine
  # Catalog view of a WarpEngine::Release: id, timestamps (see
  # WarpEngine::TimestampFields), software id, version, the paths of the
  # cartridge, source, HTML and docs assets, every asset as kind and path, and
  # +downloadCount+. Asset paths are rewritten from the file container to
  # <tt>/file/...</tt> URLs. The +download_counts+ render option, a Hash of
  # release id to count, saves a count query per release.
  class ReleaseSerializer < Blueprinter::Base
    include TimestampFields

    # URL prefix that replaces the file container path in asset paths.
    FILE_PATH_TO = "/file/"

    # Returns the configured file container path with one trailing slash, the
    # prefix rewritten to FILE_PATH_TO.
    def self.file_path_from
      "#{WarpEngine.config.file_container_path.chomp("/")}/"
    end

    # Returns the kept release assets of +release+, using the loaded
    # association when it is loaded.
    def self.assets_of(release)
      release.association(:release_assets).loaded? ? release.release_assets : release.release_assets.to_a
    end

    # Returns the <tt>/file/...</tt> path of the +kind+ asset of +release+, or
    # an empty String when it has none.
    def self.asset_path(release, kind)
      asset = assets_of(release).find { |a| a.kind == kind }
      asset ? asset.path.gsub(file_path_from, FILE_PATH_TO) : ""
    end

    field(:id)             { |r| r.id }
    field(:createdAt)      { |r| r.created_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:updatedAt)      { |r| r.updated_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:deletedAt)      { |r| r.deleted_at&.utc&.strftime(TS_FORMAT) }
    field(:softwareId)     { |r| r.software_id }
    field :version
    field(:cartridgePath)  { |r| asset_path(r, "cartridge") }
    field(:sourcePath)     { |r| asset_path(r, "source") }
    field(:htmlFolderPath) { |r| asset_path(r, "html") }
    field(:docsFolderPath) { |r| asset_path(r, "docs") }
    field(:assets) do |r|
      assets_of(r).map { |a| { kind: a.kind, path: a.path.gsub(file_path_from, FILE_PATH_TO) } }
    end
    field(:downloadCount) do |r, opts|
      counts = opts[:download_counts]
      counts ? counts.fetch(r.id, 0) : r.downloads.count
    end
  end
end
