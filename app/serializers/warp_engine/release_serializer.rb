module WarpEngine
  class ReleaseSerializer < Blueprinter::Base
    include TimestampFields

    FILE_PATH_TO = "/file/"

    # A lemezen tárolt asset-útvonalak publikus /file/ URL-lé írása configból.
    def self.file_path_from
      "#{WarpEngine.config.file_container_path.chomp("/")}/"
    end

    def self.assets_of(release)
      release.association(:release_assets).loaded? ? release.release_assets : release.release_assets.to_a
    end

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
