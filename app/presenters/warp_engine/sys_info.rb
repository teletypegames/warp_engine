module WarpEngine
  # Describes the engine as it runs, for the SysInfo admin page: the host's
  # configuration and what follows from it, as a tree of Node objects that
  # each carry a status, plus a few catalog numbers. It is computed on every
  # call, so it shows the running state, not a copy of the initializer.
  # Secrets are never shown, only whether they are set.
  #
  # The statuses, worst first: +error+ (needs fixing), +warn+ (works, with a
  # catch), +ok+, +info+ (a plain fact) and +off+ (switched off on purpose).
  # A branch takes the worst status below it.
  #
  # Live checks call the CI server (CI adapter +ping+); the page turns them
  # off per view, the host for good with <tt>sys_info_live_checks false</tt>.
  #
  #   info = WarpEngine::SysInfo.new(live: false)
  #   info.tree.each { |group| puts "#{group.label}: #{group.rolled_status}" }
  class SysInfo
    # The statuses, worst first.
    STATUSES = %w[error warn ok info off].freeze

    # The weight of each status when a branch takes the worst below it.
    RANK = { "error" => 4, "warn" => 3, "ok" => 2, "info" => 1, "off" => 0 }.freeze

    # One line of the tree.
    #
    # [key]      a stable id, unique on the page (the page remembers what is open by it)
    # [label]    what the line is about
    # [value]    what it is set to, a String (may be empty)
    # [status]   one of STATUSES
    # [chips]    short values shown as tags (kinds, platforms, URLs)
    # [hint]     a sentence that explains the value or how to fix it, or +nil+
    # [mono]     +true+ when the value is a path, URL or class name
    # [intro]    a group's one-line description, or +nil+
    # [icon]     a group's icon name, or +nil+
    # [children] the Node objects below it
    Node = Struct.new(:key, :label, :value, :status, :chips, :hint, :mono, :intro, :icon, :children, keyword_init: true) do
      # Builds a Node with the defaults: no value, no chips, no children, and
      # the status +info+ for a leaf, +off+ for a branch (whose children then
      # decide its rolled status).
      def initialize(**attributes)
        super
        self.value ||= ""
        self.chips ||= []
        self.children ||= []
        self.status ||= children.any? ? "off" : "info"
        self.mono ||= false
      end

      # Returns +true+ when the Node has children.
      def branch? = children.any?

      # Returns its own status, or the worst of its own and its children's.
      def rolled_status
        ([ status ] + children.map(&:rolled_status)).max_by { |candidate| RANK.fetch(candidate) }
      end

      # Returns +true+ when the rolled status is +error+ or +warn+.
      def problem? = %w[error warn].include?(rolled_status)

      # Returns the Node objects at the ends of its branches (itself when it has none).
      def leaves = branch? ? children.flat_map(&:leaves) : [ self ]

      # Returns a short count of what is below it, e.g. <tt>6 settings · 1 to look at</tt>.
      def tally
        problems = leaves.count(&:problem?)
        "#{leaves.size} #{leaves.size == 1 ? 'setting' : 'settings'}#{" · #{problems} to look at" if problems.positive?}"
      end
    end

    # A number on the catalog strip: its +label+, the +value+ and a +detail+ line.
    Stat = Struct.new(:label, :value, :detail, keyword_init: true)

    # [live] whether to run the live checks; they run only when the host has
    #        not turned them off (WarpEngine::Configuration#sys_info_live_checks)
    def initialize(live: true)
      @live = live && live_available?
      @checked_at = Time.current
    end

    # Returns +true+ when the live checks run for this page.
    def live? = @live

    # Returns the time the checks ran.
    attr_reader :checked_at

    # Returns +true+ when the host allows live checks and there is a CI
    # server to ask.
    def live_available?
      config.sys_info_live_checks != false && !WarpEngine.ci.is_a?(WarpEngine::CI::Null)
    end

    # Returns the groups of the tree, in page order: each a Node with an
    # +icon+, an +intro+ and its settings as children.
    def tree
      @tree ||= [ engine, publishing, adapters, identity, ci, platforms, runtimes, outlets, sync, admin_api, extras ]
    end

    # Returns how many leaves of the tree have each status, as a Hash of
    # status to count with every status present.
    def counts
      STATUSES.to_h { |status| [ status, 0 ] }.merge(tree.flat_map(&:leaves).map(&:status).tally)
    end

    # Returns the catalog numbers, as Stat objects: softwares by status,
    # releases, downloads, outlets and installed runtimes.
    def stats
      @stats ||= [ softwares_stat, releases_stat, downloads_stat, outlets_stat, runtimes_stat ]
    end

    private

    def config = WarpEngine.config

    def node(key, label, value = "", **options) = Node.new(key: key, label: label, value: value.to_s, **options)

    def group(key, label, icon:, intro:, children:) = Node.new(key: key, label: label, icon: icon, intro: intro, children: children)

    def list(values) = Array(values).map(&:to_s)

    def size(bytes) = ActiveSupport::NumberHelper.number_to_human_size(bytes)

    def duration(seconds) = ActiveSupport::Duration.build(seconds.to_i).inspect

    def ago(time)
      seconds = (Time.current - time).round
      return "updated just now" if seconds < 60
      return "updated #{seconds / 60} min ago" if seconds < 3600
      return "updated #{seconds / 3600} h ago" if seconds < 86_400

      "updated #{seconds / 86_400} days ago"
    end

    def adapter_class(object, default_class)
      object.is_a?(default_class) ? [ "built-in default", default_class.name.demodulize ] : [ "host-supplied", object.class.name ]
    end

    def engine
      group("engine", "Engine", icon: :engine, intro: "Version, file container and catalog paging", children: [
        node("engine.version", "Version", "WarpEngine #{WarpEngine::VERSION}", chips: [ "catalog API v#{WarpEngine::API_VERSION}" ]),
        site_url,
        file_container,
        node("engine.upload", "Largest upload", size(config.max_upload_size)),
        node("engine.paging", "Catalog page", "#{config.catalog_page_size} titles by default, at most #{config.catalog_max_page_size}"),
        not_counted
      ])
    end

    def site_url
      return node("engine.site", "Site URL", config.site_url, status: "ok", mono: true) if config.site_url.present?

      node("engine.site", "Site URL", "not set", status: "warn", hint: "Links in the API stay relative; set site_url in the initializer.")
    end

    def file_container
      path = config.file_container_path.to_s
      if !File.directory?(path)
        node("engine.container", "File container", path, status: "error", mono: true, chips: [ "missing" ],
                                                         hint: "Uploads and shelves need the folder; create it or fix file_container_path.")
      elsif !File.writable?(path)
        node("engine.container", "File container", path, status: "error", mono: true, chips: [ "exists", "NOT writable" ],
                                                         hint: "Uploads fail until the process may write into it.")
      else
        node("engine.container", "File container", path, status: "ok", mono: true, chips: [ "exists", "writable" ])
      end
    end

    def not_counted
      agents = Array(config.ignored_user_agents).map { |agent| agent.is_a?(Regexp) ? agent.inspect : agent.to_s }
      return node("engine.ignored", "Not counted", "every client is counted") if agents.empty?

      node("engine.ignored", "Not counted", "", chips: agents, hint: "User agents the download statistics leave out.")
    end

    def publishing
      database = config.application_token_source.to_s == "database"
      children = [ node("publishing.credentials", "Build credentials",
                        database ? "application tokens from the database" : "the shared UPDATE_SECRET",
                        status: "ok", chips: database ? %w[scopes expiry] : []) ]
      children << if database
        node("publishing.secret", "UPDATE_SECRET", "not needed with database tokens", status: "off")
      elsif config.update_secret.present?
        node("publishing.secret", "UPDATE_SECRET", "set", status: "ok")
      else
        node("publishing.secret", "UPDATE_SECRET", "not set", status: "error", hint: "Every upload and publish is refused until it is set.")
      end
      children << node("publishing.owners", "Token owners", config.application_token_owner_class.presence || "none", mono: true) if database
      children << if config.enforce_software_ownership
        node("publishing.ownership", "Software ownership", "enforced: a token publishes only its owner's software", status: "ok")
      else
        node("publishing.ownership", "Software ownership", "not enforced: any token publishes any software")
      end
      group("publishing", "Publishing", icon: :key, intro: "How a pipeline proves it may upload and publish", children: children)
    end

    def adapters
      storage_kind, storage_class = adapter_class(WarpEngine.storage, WarpEngine::Storage::LocalAdapter)
      images_kind, images_class = adapter_class(WarpEngine.images, WarpEngine::Images::HostModel)
      access = if WarpEngine::AccessPolicy.open?
        node("adapters.access", "Access policy", "open: every title is free to download", status: "ok")
      else
        node("adapters.access", "Access policy", "host-supplied", status: "ok", chips: [ WarpEngine.access_policy.class.name ])
      end
      group("adapters", "Storage, images and access", icon: :plug, intro: "The pluggable parts, default unless the host supplied its own",
                                                      children: [
                                                        node("adapters.storage", "Storage", storage_kind, status: "ok", chips: [ storage_class ]),
                                                        node("adapters.images", "Images", images_kind, status: "ok", chips: [ images_class, "model #{config.image_class_name}" ]),
                                                        access,
                                                        store_registry
                                                      ])
    end

    def store_registry
      registry = WarpEngine::StoreRegistry.current
      case registry
      when nil
        node("adapters.stores", "Store registry", "off: GET /api/stores answers 404", status: "off")
      when WarpEngine::StoreRegistry::Own
        name = config.store_name.presence || "the host name of its address"
        node("adapters.stores", "Store registry", "this catalog alone, as #{name}", status: "ok")
      when WarpEngine::StoreRegistry::Fixed
        node("adapters.stores", "Store registry", "a fixed list", status: "ok", chips: [ "#{registry.entries.size} entries" ])
      else
        node("adapters.stores", "Store registry", "host-supplied", status: "ok", chips: [ registry.class.name ])
      end
    end

    def identity
      intro = "Device code sign-in for clients without a browser (RFC 8628)"
      unless WarpEngine.identity_configured?
        return group("signin", "Client sign-in", icon: :user, intro: intro, children: [
          node("signin.off", "Sign-in", "off", status: "off", hint: "No access_token_owner_class is configured, so clients cannot sign in.")
        ])
      end

      verification = if config.identity_verification_url.present?
        node("signin.verification", "Verification page", config.identity_verification_url, status: "ok", mono: true)
      else
        node("signin.verification", "Verification page", "not set", status: "warn",
                                                                    hint: "Clients show the engine's default page; set identity_verification_url to send people to the host's.")
      end
      group("signin", "Client sign-in", icon: :user, intro: intro, children: [
        node("signin.model", "Account model", config.access_token_owner_class, status: "ok", mono: true),
        verification,
        node("signin.code", "Device code", "valid for #{duration(config.device_code_ttl)}, polled every #{duration(config.device_code_interval)}"),
        node("signin.browser", "Browser sessions", config.subject_resolver ? "recognised (subject resolver set)" : "not recognised",
                                                   status: config.subject_resolver ? "ok" : "off")
      ])
    end

    def ci
      adapter = WarpEngine.ci
      if adapter.is_a?(WarpEngine::CI::Null)
        return group("ci", "CI", icon: :branch, intro: "Builds, pipeline configs and secrets", children: [
          node("ci.off", "CI", "off", status: "off", hint: "This host builds nothing; /build/config and the pipeline actions are disabled.")
        ])
      end

      children = Array(adapter.respond_to?(:settings) ? adapter.settings : []).each_with_index.map do |(label, value), index|
        text = value.to_s
        node("ci.setting.#{index}", label, text, status: text.start_with?("not set") ? "warn" : "ok", mono: text.match?(%r{\A\w+://}))
      end
      children << connection(adapter)
      children << live_check(adapter)
      children << node("ci.upload", "Pipelines upload to", adapter.update_server || "the URL the request came in on", mono: adapter.update_server.present?)
      built = adapter.platforms.map do |name, spec|
        chips = [ spec[:exporter].presence && "exporter", spec[:web_shell].presence && "web shell", spec[:forge_release] && "forge release" ].compact
        node("ci.platform.#{name}", name, spec[:builder].presence || "no builder", status: spec[:builder].present? ? "ok" : "warn", mono: true, chips: chips)
      end
      children << node("ci.platforms", "Platforms it builds", "#{built.size} platforms", children: built) if built.any?
      group("ci", "CI · #{adapter.name}", icon: :branch, intro: "Builds, pipeline configs and secrets", children: children)
    end

    def connection(adapter)
      return node("ci.configured", "Configuration", "complete", status: "ok") if adapter.configured?

      node("ci.configured", "Configuration", "incomplete", status: "error", hint: "The server URL or the API token is missing.")
    end

    def live_check(adapter)
      unless live?
        hint = config.sys_info_live_checks == false ? "Turned off for good with sys_info_live_checks false." : "Turn live checks on to call the CI server."
        return node("ci.live", "Live check", "off", status: "off", hint: hint)
      end

      ping = adapter.ping
      return node("ci.live", "Live check", "no check for this adapter", status: "off") if ping.nil?

      if ping.ok?
        node("ci.live", "Live check", ping.detail, status: "ok", chips: [ "#{ping.ms} ms" ])
      else
        node("ci.live", "Live check", ping.detail, status: "error", chips: [ "#{ping.ms} ms" ],
                                                   hint: "Check the server URL and that the API token is still valid.")
      end
    end

    def platforms
      built = WarpEngine.ci.platforms
      children = WarpEngine::Platform.all.map do |platform|
        origin = if platform.legacy? then "host (legacy service)"
        elsif WarpEngine::Platform.registration(platform.name) then WarpEngine::Platform.builtin?(platform.name) ? "host (replaces built-in)" : "host"
        else "built-in"
        end
        built_here = built.key?(platform.name)
        node("platforms.#{platform.name}", "#{platform.name} · #{platform.label}", origin,
             status: built_here ? "ok" : "info", chips: built_here ? [] : [ "not built here" ],
             children: [
               node("platforms.#{platform.name}.accepts", "Accepts", "", chips: list(platform.expected_kinds)),
               node("platforms.#{platform.name}.requires", "Requires", list(platform.required_kinds).empty? ? "nothing" : "", chips: list(platform.required_kinds)),
               node("platforms.#{platform.name}.builds", "Pipeline builds", built_here ? "" : "not built here", chips: built_here ? list(platform.built_kinds) : []),
               node("platforms.#{platform.name}.release", "Releases from", platform.release_rule || "marker decides"),
               platform_web(platform)
             ])
      end
      group("platforms", "Platforms", icon: :gamepad, intro: "#{children.size} platforms; a publish fails without a required kind", children: children)
    end

    def platform_web(platform)
      key = "platforms.#{platform.name}.web"
      bindings = platform.all_web_bindings
      return node(key, "Plays on the web in", "no runtime", status: "off") if bindings.empty?

      broken = bindings.select(&:enabled).reject(&:valid?)
      chips = bindings.map do |binding|
        [ binding.key, binding.key == binding.runtime ? nil : "(#{binding.runtime})", binding.default ? "default" : nil,
          binding.enabled ? nil : "off" ].compact.join(" ")
      end
      if broken.any?
        return node(key, "Plays on the web in", "#{broken.size} broken", status: "error", chips: chips,
                                                                           hint: broken.map { |binding| "#{binding.key}: #{binding.errors.join(', ')}" }.join("; "))
      end

      node(key, "Plays on the web in", "", status: "ok", chips: chips)
    end

    def runtimes
      installed = WarpEngine::RuntimeVersion.kept.includes(:runtime_components).to_a
      children = WarpEngine::Runtime.all.map { |runtime| runtime_node(runtime, installed.select { |version| version.name == runtime.name }) }
      group("runtimes", "Runtimes", icon: :code, intro: "Where the releases play on the web; rake warp_engine:runtimes:install fetches them",
                                    children: children)
    end

    def runtime_node(runtime, installed)
      key = "runtimes.#{runtime.name}"
      origin = WarpEngine::Runtime.builtin?(runtime.name) && !config.runtimes.key?(runtime.name) ? "built-in" : "host"
      current = runtime.current_version
      node(key, "#{runtime.name} · #{runtime.label}", origin, status: current ? "ok" : "info", children: [
        runtime_version_node(key, runtime, installed, current),
        node("#{key}.source", "Source", runtime.download? ? "downloaded, SHA-256 checked" : "uploaded by a build",
             chips: runtime.download? ? runtime.definition.versions.keys : []),
        runtime_components_node(key, runtime, current),
        node("#{key}.platforms", "Platforms", runtime.platforms.empty? ? "none bound" : "",
             status: runtime.platforms.empty? ? "off" : "info", chips: runtime.platforms),
        node("#{key}.size", "On disk", installed.empty? ? "nothing installed" : size(installed.sum(&:size_bytes)),
             chips: installed.map { |version| "#{version.version}: #{version.releases.count} releases" }),
        runtime_verify_node(key, installed)
      ])
    end

    def runtime_version_node(key, runtime, installed, current)
      chosen = runtime.chosen_version
      label = config.runtime_versions.key?(runtime.name) ? "chosen by the host" : "newest"
      if current
        node("#{key}.version", "Version", current.version, status: "ok", chips: [ label ])
      elsif runtime.upload? && chosen.nil?
        node("#{key}.version", "Version", "none uploaded", status: runtime.platforms.empty? ? "info" : "warn",
                                                          hint: "A build installs it through POST /build/runtime; until then its platforms play from html assets.")
      else
        node("#{key}.version", "Version", "#{chosen} not installed", status: runtime.platforms.empty? ? "info" : "error",
                                                                     chips: installed.map(&:version),
                                                                     hint: runtime.download? ? "Run rake warp_engine:runtimes:install NAME=#{runtime.name}." : "Upload it through POST /build/runtime.")
      end
    end

    def runtime_components_node(key, runtime, current)
      needed = runtime.required_components.flat_map { |kind, keys| keys.map { |component| [ kind, component ] } }
      return node("#{key}.components", "Components", "none needed") if needed.empty?

      missing = current ? needed.reject { |kind, component| current.component?(kind, component) } : needed
      chips = needed.map { |kind, component| "#{kind} #{component}#{' (missing)' if missing.include?([ kind, component ])}" }
      extra = current ? current.runtime_components.map { |component| [ component.kind, component.key ] } - needed : []
      chips += extra.map { |kind, component| "#{kind} #{component} (unused)" }
      return node("#{key}.components", "Components", "", status: "ok", chips: chips) if missing.empty?

      node("#{key}.components", "Components", "#{missing.size} missing", status: current ? "error" : "info", chips: chips,
                                                                           hint: "rake warp_engine:runtimes:install NAME=#{runtime.name} installs what the bindings need.")
    end

    def runtime_verify_node(key, installed)
      return node("#{key}.verify", "Files", "nothing installed", status: "off") if installed.empty?
      return node("#{key}.verify", "Files", "not checked", hint: "The live checks read every file and compare its SHA-256.") unless live?

      service = WarpEngine::RuntimeInstallService.new
      broken = installed.to_h { |version| [ version.version, service.verify(version) ] }.reject { |_, files| files.empty? }
      return node("#{key}.verify", "Files", "intact", status: "ok") if broken.empty?

      node("#{key}.verify", "Files", "#{broken.values.sum(&:size)} damaged or missing", status: "error",
                                                                                        chips: broken.flat_map { |version, files| files.map { |file| "#{version}/#{file}" } })
    end

    def outlets
      intro = "Where the catalog leaves the engine; refreshed by OutletRefreshJob"
      all = WarpEngine::Outlets.validate!
      group("outlets", "Outlets", icon: :send, intro: intro, children: all.map { |outlet| outlet_node(outlet) })
    rescue WarpEngine::ConfigurationError => e
      group("outlets", "Outlets", icon: :send, intro: intro, children: [
        node("outlets.invalid", "Configuration", "invalid", status: "error", hint: e.message)
      ])
    end

    def outlet_node(outlet)
      case outlet
      when WarpEngine::Outlets::Wecp
        node("outlets.wecp", "wecp", "served", status: "ok", chips: [ "/api", "/file", "API v#{WarpEngine::API_VERSION}" ])
      when WarpEngine::Outlets::Shelf then shelf_node(outlet)
      when WarpEngine::Outlets::Assembly64 then assembly64_node(outlet)
      else node("outlets.#{outlet.key}", outlet.key, outlet.type, status: "ok", chips: list(outlet.platforms))
      end
    end

    def shelf_node(shelf)
      key = "outlets.#{shelf.key}"
      entries, skipped = shelf.plan
      names = shelf.folders? ? "folders of up to #{shelf.name_length}" : "#{shelf.name_length} characters"
      children = [
        shelf_folder(shelf, key),
        node("#{key}.layout", "Layout", shelf.layout, chips: [ shelf.extension.presence, names, shelf.preview && "preview #{shelf.preview}" ].compact),
        node("#{key}.statuses", "Lists", "", chips: shelf.offer.listed_statuses),
        if shelf.urls.any?
          node("#{key}.urls", "Served at", "", status: "ok", chips: shelf.urls)
        else
          node("#{key}.urls", "Served at", "not published", status: "off")
        end
      ]
      if skipped.any?
        children << node("#{key}.skipped", "Left out", "#{skipped.size} #{skipped.size == 1 ? 'title' : 'titles'}", status: "warn",
                                                       hint: skipped.map(&:to_s).first(5).join(" · ").truncate(400))
      end
      count = "#{entries.size} #{shelf.folders? ? 'folders' : 'titles'}"
      node(key, shelf.key, "shelf · #{count}", chips: [ shelf.path ], children: children)
    end

    def shelf_folder(shelf, key)
      directory = shelf.directory
      unless File.directory?(directory)
        return node("#{key}.folder", "Folder", directory, status: "warn", mono: true, chips: [ "not built yet" ],
                                                          hint: "The next publish builds it; rake warp_engine:outlets:sync builds it now.")
      end
      unless File.writable?(directory)
        return node("#{key}.folder", "Folder", directory, status: "error", mono: true, chips: [ "NOT writable" ],
                                                          hint: "The sync cannot write; readers keep the previous files.")
      end

      index = File.join(directory, WarpEngine::Outlets::Shelf::IndexFile::NAME)
      return node("#{key}.folder", "Folder", directory, status: "warn", mono: true, chips: [ "no INDEX.TXT" ]) unless File.file?(index)

      node("#{key}.folder", "Folder", directory, status: "ok", mono: true, chips: [ "INDEX.TXT", ago(File.mtime(index)) ])
    end

    def assembly64_node(outlet)
      key = "outlets.#{outlet.key}"
      offer = begin
        titles = outlet.offer.items.map(&:software).uniq.size
        node("#{key}.offer", "On offer", "#{titles} #{titles == 1 ? 'title' : 'titles'}", status: titles.positive? ? "ok" : "warn",
                                                                                          chips: outlet.platforms + outlet.kinds)
      rescue StandardError => e
        node("#{key}.offer", "On offer", "the catalog cannot be read", status: "error", hint: "#{e.class}: #{e.message}".truncate(200))
      end
      node(key, outlet.key, "served", chips: outlet.hosts.presence || [ "any host" ], children: [
        node("#{key}.path", "Path", "/#{WarpEngine::Outlets::Assembly64::PATH}", mono: true),
        node("#{key}.repo", "Repository", outlet.repo_name, chips: [ outlet.repo ]),
        node("#{key}.clients", "Clients", outlet.client_ids.any? ? "" : "any Client-Id", chips: outlet.client_ids),
        offer
      ])
    end

    def sync
      settings = WarpEngine::Sync.config
      unless settings.enabled?
        return group("sync", "Sync", icon: :send, intro: "Off", children: [
          node("sync.off", "Sync", "off", status: "off", hint: "Set enabled in the sync block of the initializer to push releases to other engines.")
        ])
      end

      servers = WarpEngine::SyncServer.active.order(:label).map do |server|
        status = server.last_error.present? ? "warn" : (server.last_synced_at ? "ok" : "info")
        node("sync.server.#{server.id}", server.label, server.base_url, status: status, mono: true,
                                                                        chips: [ server.last_synced_at ? ago(server.last_synced_at).sub("updated", "pushed") : "no push yet" ],
                                                                        hint: server.last_error.presence&.truncate(160))
      end
      filters = WarpEngine::Sync::Configuration::LISTS.filter_map do |name|
        values = Array(settings.public_send(name))
        "#{name}: #{values.join(', ')}" if values.any?
      end
      children = [
        node("sync.servers", "Servers", servers.any? ? "#{servers.size} active" : "none", status: servers.any? ? "ok" : "warn",
                                                                                   children: servers,
                                                                                   hint: servers.any? ? nil : "Add one under Sync Servers; nothing is pushed until then."),
        node("sync.switch", "Per-software switch", settings.software_switch ? settings.software_switch.to_s : "off"),
        node("sync.filters", "Filters", filters.any? ? "" : "none", chips: filters),
        node("sync.events", "Event log", settings.events? ? "#{settings.verbose_events? ? 'verbose' : 'on'}, kept #{settings.event_retention_days} days" : "off",
             status: settings.events? ? "ok" : "off")
      ]
      children << sync_failures if settings.events?
      group("sync", "Sync", icon: :send, intro: "On: releases are pushed to other engines", children: children)
    end

    def sync_failures
      failed = WarpEngine::SyncEvent.failed.where(created_at: 1.day.ago..).count
      node("sync.failures", "Failed pushes, last 24 hours", failed.to_s, status: failed.positive? ? "warn" : "ok")
    end

    def admin_api
      api = config.admin_api
      intro = api.enabled? ? "On, at #{WarpEngine::AdminApi.url_path}#{', read-only' if api.read_only?}" : "Off"
      unless api.enabled?
        return group("adminapi", "Admin API", icon: :terminal, intro: intro, children: [
          node("adminapi.off", "Admin API", "off", status: "off")
        ])
      end

      limit = api.rate_limit ? "#{api.rate_limit[:to]} requests per #{duration(api.rate_limit[:within])}" : "none"
      group("adminapi", "Admin API", icon: :terminal, intro: intro, children: [
        node("adminapi.resources", "Resources", api.resources == :all ? "all" : "", status: "ok", chips: api.resources == :all ? [] : list(api.resources)),
        node("adminapi.owners", "Tokens owned by", api.owner_class_name.presence || "anyone with an admin-scoped token", mono: api.owner_class_name.present?),
        node("adminapi.paging", "Page size", "#{api.page_size}, at most #{api.max_page_size}"),
        node("adminapi.limit", "Rate limit", limit, status: api.rate_limit ? "ok" : "warn",
                                                    hint: api.rate_limit ? nil : "Without a rate limit a leaked token can hammer the API."),
        node("adminapi.openapi", "OpenAPI document", api.openapi_requires_auth? ? "needs a token" : "public"),
        node("adminapi.docs", "Docs page", api.docs_ui? ? "served" : "off", status: api.docs_ui? ? "info" : "off"),
        mcp_node(api)
      ])
    end

    def mcp_node(api)
      return node("adminapi.mcp", "MCP server", "off", status: "off") unless api.mcp?
      return node("adminapi.mcp", "MCP server", "on", status: "error", hint: "The mcp gem is missing from the host's Gemfile.") unless defined?(::MCP)

      version = defined?(::MCP::VERSION) ? "mcp gem #{::MCP::VERSION}" : "mcp gem"
      node("adminapi.mcp", "MCP server", "on", status: "ok", chips: [ version ] + list(api.mcp_exclude).map { |name| "without #{name}" })
    end

    def extras
      resources = Array(config.additional_resources)
      children = resources.map do |resource|
        node("extras.#{resource.subject}.#{resource.association}", "#{resource.subject} · #{resource.association}", resource.label,
             chips: [ resource.multiple ? "several" : "one", resource.api? ? "in the Admin API" : nil ].compact)
      end
      children = [ node("extras.none", "Host records", "none", status: "off") ] if children.empty?
      group("extras", "Additional resources", icon: :plus, intro: "Host records edited on the engine's admin pages", children: children)
    end

    def softwares_stat
      by_status = WarpEngine::Software.kept.group(:status).count
      detail = by_status.sort_by { |_, count| -count }.map { |status, count| "#{count} #{status.presence || 'no status'}" }.join(" · ")
      Stat.new(label: "Softwares", value: by_status.values.sum, detail: detail.presence || "none yet")
    end

    def releases_stat
      releases = WarpEngine::Release.kept
      Stat.new(label: "Releases", value: releases.count, detail: "#{releases.where(created_at: Time.current.beginning_of_month..).count} this month")
    end

    def downloads_stat
      downloads = WarpEngine::Download.kept
      today = downloads.where(created_at: Time.current.beginning_of_day..).count
      month = downloads.where(created_at: 30.days.ago..).count
      Stat.new(label: "Downloads", value: today, detail: "today · #{ActiveSupport::NumberHelper.number_to_delimited(month)} in 30 days")
    end

    def runtimes_stat
      versions = WarpEngine::RuntimeVersion.kept
      bound = WarpEngine::Release.kept.where.not(runtime_version_id: nil).count
      Stat.new(label: "Runtimes", value: versions.count,
               detail: "#{versions.distinct.count(:name)} runtimes · #{size(versions.sum(:size_bytes))} · #{bound} releases play in one")
    end

    def outlets_stat
      types = WarpEngine::Outlets.validate!.map(&:type).tally
      Stat.new(label: "Outlets", value: types.values.sum, detail: types.map { |type, count| "#{count} #{type}" }.join(" · "))
    rescue WarpEngine::ConfigurationError
      Stat.new(label: "Outlets", value: "?", detail: "configuration invalid")
    end
  end
end
