module WarpEngine
  # Serves the store engines of WarpEngine::StoreClients for this catalog: the
  # release a machine runs, the store config it installs with, and the
  # installer that puts both on the machine. What the host set on its
  # WarpEngine::StoreClient wins; the rest is worked out from the catalog.
  class StoreClientService
    # The release a store engine runs: the catalog +software+ name, the
    #     # <tt>/file/</tt>) and its +size+ in bytes (+nil+ when the storage does
    # not keep the file on this machine).
    Target = ::Data.define(:software, :version, :path, :size)

    # The template of the installer #installer renders.
    INSTALLER = File.expand_path("../../../lib/warp_engine/store_clients/install.sh.erb", __dir__)

    # Returns the Target the machines of +client+ run: the pinned version of
    # the WarpEngine::StoreClient, or else the newest stable release of the
    # store engine's software that has its archive. Raises
    # ActiveRecord::RecordNotFound when +client+ is not a store engine or
    # there is no such release.
    def release(client:)
      definition = client_definition(client)
      record = StoreClient.for(definition.key)
      software = Software.kept.find_by!(name: record.software_name.presence || definition.software)
      found = pick_release(software, record.pinned_version.presence)
      asset = found&.release_assets&.find { |a| a.kind == "cartridge" }
      raise ActiveRecord::RecordNotFound, "#{software.name} has no release to run" if asset.nil?

      path = asset.path.to_s.delete_prefix("#{WarpEngine.config.file_container_path.chomp("/")}/")
      Target.new(software: software.name, version: found.version, path: path, size: size_of(path))
    end

    # Returns the store config of +client+ as a Hash: its template with this
    # catalog's +base_url+, the store's name, id, folders, statuses and logo,
    # the platforms the engine has, and <tt>store.api.release</tt> set to
    # +release_path+ so the engine updates itself. Raises
    # ActiveRecord::RecordNotFound when +client+ is not a store engine.
    def config(client:, base_url:, release_path:)
      definition = client_definition(client)
      record = StoreClient.for(definition.key)
      base_url = base_url.to_s.chomp("/")
      name = record.name.presence || default_name(base_url)
      key = record.store_key.presence || default_key(base_url)
      definition.config_template.tap do |config|
        config["store"].merge!("id" => key, "name" => name, "base_url" => base_url)
        config["store"]["api"]["release"] = release_path
        config["paths"]["subfolder"] = record.subfolder.presence || key
        config["emulationstation"]["folder_name"] = name if config.key?("emulationstation")
        config["catalog"]["statuses"] = Array(record.statuses).presence || SoftwareStatus.default_visible_keys
        config["platforms"].select! { |platform, _| Platform.exists?(platform) }
        apply_logo(config, Array(record.logo_urls))
      end
    end

    # Returns the installer of +client+, a shell script: it downloads the
    # engine archive of the Target from +archive_url+, unpacks it and runs
    # the engine's own <tt>install.sh</tt> with the store config at
    # +config_url+. +install_url+ is where the script itself is served, for
    # its usage line. Raises ActiveRecord::RecordNotFound as #release does.
    def installer(client:, base_url:, install_url:, config_url:, archive_url:)
      definition = client_definition(client)
      found = release(client: client)
      name = StoreClient.for(definition.key).name.presence || default_name(base_url.to_s.chomp("/"))
      ERB.new(File.read(INSTALLER), trim_mode: "-").result_with_hash(
        name: name, label: definition.label, release: found,
        install_url: install_url, config_url: config_url, archive_url: archive_url
      )
    end

    private

    def client_definition(client)
      StoreClients.find(client) || raise(ActiveRecord::RecordNotFound, "#{client} is not a store engine")
    end

    def pick_release(software, pinned)
      releases = software.releases.includes(:release_assets).to_a
      return releases.find { |r| r.version == pinned } if pinned

      WarpEngine::Release.latest(releases.select { |r| r.release_assets.any? { |a| a.kind == "cartridge" } })
    end

    def size_of(path)
      location = WarpEngine.storage.locate(path)
      location.file? && File.file?(location.path) ? File.size(location.path) : nil
    end

    def default_name(base_url)
      name = WarpEngine.config.store_name.to_s.strip
      name.empty? ? URI(base_url).host.to_s : name
    end

    def default_key(base_url)
      URI(base_url).host.to_s.split(".").reject { |part| part == "www" }.first.to_s
                   .downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-").presence || "store"
    end

    def apply_logo(config, urls)
      return if urls.empty?

      config.dig("emulationstation", "menu")&.store("logo", urls)
      config["playlist"]["icon"] = urls.find { |url| url.downcase.end_with?(".png") } || urls.first if config.key?("playlist")
    end
  end
end
