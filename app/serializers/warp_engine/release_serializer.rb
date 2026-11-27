module WarpEngine
  # Catalog view of a WarpEngine::Release: id, timestamps (see
  # WarpEngine::TimestampFields), software id, version, +channel+, the paths of the
  # package (+packagePath+, and under its old name +cartridgePath+ for the
  # clients of API 5), source, HTML and docs assets, every asset as kind and path
  # (and <tt>launch: false</tt> for a kind a client only downloads, see
  # WarpEngine::AssetKind),
  # +downloadCount+, and how it plays on the web: +playUrl+ (the page of the
  # runtime it was published with, <tt>/play/<name>/<version></tt>, else its
  # +html+ folder, else empty) and +players+ (every web binding of the
  # platform it can play in now: +binding+, +runtime+, +label+, +url+,
  # +default+). The kinds the software turns off
  # (WarpEngine::Software#disabled_kinds) are left out, and with the web
  # turned off it plays nowhere. Asset paths are rewritten from the file container to
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
    # association when it is loaded, without the kinds its software turns
    # off (WarpEngine::Software#kind_disabled?).
    def self.assets_of(release)
      assets = release.association(:release_assets).loaded? ? release.release_assets : release.release_assets.to_a
      software = release.software
      software ? assets.reject { |asset| software.kind_disabled?(asset.kind) } : assets
    end

    # Returns the <tt>/file/...</tt> path of the +kind+ asset of +release+, or
    # an empty String when it has none.
    def self.asset_path(release, kind)
      asset = assets_of(release).find { |a| a.kind == kind }
      asset ? asset.path.gsub(file_path_from, FILE_PATH_TO) : ""
    end

    # URL prefix of the web player pages.
    PLAY_PATH = "/play/"

    # Returns the URL the release plays at: its runtime page when it was
    # published bound to an installed runtime, else its +html+ folder, else
    # an empty String. A release whose metadata says <tt>web.enabled:
    # false</tt>, or whose software turns the web off, does not play on the
    # web at all.
    def self.play_url(release)
      return "" if release.web_options.to_h["enabled"] == false || release.software&.web_disabled?
      return play_path(release) if bound?(release)

      asset_path(release, "html")
    end

    # Returns the web bindings +release+ can play in now, as Hashes of
    # +binding+, +runtime+, +label+, +url+ and +default+ (the release's own
    # binding); empty when it does not play in a runtime.
    def self.players(release)
      platform = WarpEngine::Platform.for(release.software)
      return [] if platform.nil? || release.web_options.to_h["enabled"] == false

      kinds = assets_of(release).map(&:kind)
      platform.web_bindings.filter_map do |binding|
        next unless kinds.include?(binding.payload)

        version = player_version(release, binding)
        next unless version && WarpEngine::Publish::WebBinder.components_installed?(version, binding)

        own = binding.key == release.web_binding
        { binding: binding.key, runtime: binding.runtime, label: version.label,
          url: own ? play_path(release) : "#{play_path(release)}/#{binding.key}", default: own }
      end
    end

    # Returns +true+ when +release+ was published bound to a runtime version
    # that is still installed.
    def self.bound?(release)
      release.web_binding.present? && release.runtime_version_id.present? &&
        WarpEngine::Current.runtime_version(release.runtime_version_id).present?
    end

    # Returns the <tt>/play/<name>/<version></tt> path of +release+.
    def self.play_path(release)
      "#{PLAY_PATH}#{ERB::Util.url_encode(release.software.name)}/#{ERB::Util.url_encode(release.version)}"
    end

    # Returns the WarpEngine::RuntimeVersion +release+ plays in with
    # +binding+: its own for its own binding, else the runtime's current one.
    def self.player_version(release, binding)
      return WarpEngine::Current.runtime_version(release.runtime_version_id) if binding.key == release.web_binding

      runtime = binding.runtime_object
      runtime && WarpEngine::Current.current_runtime_version(runtime)
    end
    private_class_method :player_version

    field(:id)             { |r| r.id }
    field(:createdAt)      { |r| r.created_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:updatedAt)      { |r| r.updated_at&.utc&.strftime(TS_FORMAT) || GO_ZERO_TIME }
    field(:deletedAt)      { |r| r.deleted_at&.utc&.strftime(TS_FORMAT) }
    field(:softwareId)     { |r| r.software_id }
    field :version
    field :channel
    field(:packagePath)    { |r| asset_path(r, "package") }
    field(:cartridgePath)  { |r| asset_path(r, "package") }
    field(:sourcePath)     { |r| asset_path(r, "source") }
    field(:htmlFolderPath) { |r| asset_path(r, "html") }
    field(:docsFolderPath) { |r| asset_path(r, "docs") }
    field(:assets) do |r|
      assets_of(r).map do |a|
        asset = { kind: a.kind, path: a.path.gsub(file_path_from, FILE_PATH_TO) }
        WarpEngine::AssetKinds.launchable?(a.kind) ? asset : asset.merge(launch: false)
      end
    end
    field(:playUrl) { |r| play_url(r) }
    field(:players) { |r| players(r) }
    field(:downloadCount) do |r, opts|
      counts = opts[:download_counts]
      counts ? counts.fetch(r.id, 0) : r.downloads.count
    end
  end
end
