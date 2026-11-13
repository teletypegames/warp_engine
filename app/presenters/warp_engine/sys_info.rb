module WarpEngine
  # Describes the engine's live configuration (what the host's initializer
  # set, and what follows from it) in words an admin reads, for the SysInfo
  # admin page. It is computed on every call, so it shows the running state,
  # not a copy of the initializer. Secrets are never shown, only whether they
  # are set.
  #
  #   WarpEngine::SysInfo.new.sections.each do |section|
  #     puts section.title
  #     section.rows.each { |label, value| puts "  #{label}: #{value}" }
  #   end
  class SysInfo
    # One block of the page: a +title+, an +intro+ sentence, <tt>[label, value]</tt>
    # +rows+ and +tables+ (each a Table).
    Section = Struct.new(:title, :intro, :rows, :tables, keyword_init: true)

    # A table inside a Section: its +title+, +columns+ and +rows+ (Arrays of
    # Strings, one per column).
    Table = Struct.new(:title, :columns, :rows, keyword_init: true)

    # Returns every Section, in page order.
    def sections
      [ engine, publishing, storage, identity, ci, platforms, outlets, admin_api, extras ]
    end

    private

    def config = WarpEngine.config

    def yes_no(value, yes = "yes", no = "no") = value ? yes : no

    def set_or_not(value, hint = nil) = value.present? ? "set" : [ "not set", hint ].compact.join(" ")

    def list(values, empty = "none") = Array(values).map(&:to_s).presence&.join(", ") || empty

    def size(bytes) = ActiveSupport::NumberHelper.number_to_human_size(bytes)

    def duration(seconds) = ActiveSupport::Duration.build(seconds.to_i).inspect

    def adapter_name(object, default_class)
      object.is_a?(default_class) ? "built-in default (#{default_class.name.demodulize})" : "host-supplied #{object.class.name}"
    end

    def engine
      container = config.file_container_path.to_s
      state = if File.directory?(container)
                File.writable?(container) ? "exists, writable" : "exists, NOT writable"
      else
                "does NOT exist"
      end
      Section.new(
        title: "Engine",
        intro: "WarpEngine #{WarpEngine::VERSION}, serving catalog API envelope version #{WarpEngine::API_VERSION}.",
        rows: [
          [ "Site URL", config.site_url.presence || "not set: links in the API are relative" ],
          [ "File container", "#{container} (#{state})" ],
          [ "Largest upload", size(config.max_upload_size) ],
          [ "Catalog page", "#{config.catalog_page_size} titles by default, at most #{config.catalog_max_page_size}" ],
          [ "Downloads not counted from", list(config.ignored_user_agents.map { |agent| agent.is_a?(Regexp) ? agent.inspect : agent }, "every client is counted") ]
        ],
        tables: []
      )
    end

    def publishing
      database = config.application_token_source.to_s == "database"
      rows = [
        [ "Build credentials", database ? "application tokens from the database (with scopes and expiry)" : "the shared UPDATE_SECRET" ],
        [ "Shared secret (UPDATE_SECRET)", set_or_not(config.update_secret, database ? "(not needed with database tokens)" : "— uploads are refused") ]
      ]
      rows << [ "Token owners", config.application_token_owner_class.presence || "none" ] if database
      rows << [ "Software ownership", yes_no(config.enforce_software_ownership, "enforced: a token publishes only its owner's software", "not enforced") ]
      Section.new(title: "Publishing", intro: "How a pipeline proves it may upload and publish a build.", rows: rows, tables: [])
    end

    def storage
      Section.new(
        title: "Storage, images and access",
        intro: "The pluggable parts: each is the engine's default unless the host supplied its own.",
        rows: [
          [ "Storage", adapter_name(WarpEngine.storage, WarpEngine::Storage::LocalAdapter) ],
          [ "Images", "#{adapter_name(WarpEngine.images, WarpEngine::Images::HostModel)}, model #{config.image_class_name}" ],
          [ "Access policy", WarpEngine::AccessPolicy.open? ? "open: every title is free to download" : "host-supplied #{WarpEngine.access_policy.class.name}" ]
        ],
        tables: []
      )
    end

    def identity
      unless WarpEngine.identity_configured?
        return Section.new(title: "Client sign-in", intro: "Off: no access_token_owner_class is configured, so clients cannot sign in.", rows: [], tables: [])
      end

      Section.new(
        title: "Client sign-in",
        intro: "On: clients without a browser sign in with a device code (RFC 8628).",
        rows: [
          [ "Account model", config.access_token_owner_class.to_s ],
          [ "Verification page", config.identity_verification_url.presence || "not set" ],
          [ "Device code", "valid for #{duration(config.device_code_ttl)}, polled every #{duration(config.device_code_interval)}" ],
          [ "Browser sessions", config.subject_resolver ? "recognised (subject resolver set)" : "not recognised" ]
        ],
        tables: []
      )
    end

    def ci
      adapter = WarpEngine.ci
      intro = if adapter.is_a?(WarpEngine::CI::Null)
                "Off: this host builds nothing; /build/config and the pipeline actions are disabled."
      else
                "#{adapter.name}, #{adapter.configured? ? 'connected' : 'NOT connected (server URL or API token missing)'}."
      end
      rows = adapter.respond_to?(:settings) ? adapter.settings.map { |label, value| [ label, value.to_s ] } : []
      rows << [ "Pipelines upload to", adapter.update_server || "the URL the request came in on" ] unless adapter.is_a?(WarpEngine::CI::Null)
      platform_rows = adapter.platforms.map do |name, spec|
        [ name, spec[:builder].presence || "—", spec[:exporter].presence || "—", spec[:tools].presence || "alpine (installs on every run)",
          spec[:web_shell].presence || "—", yes_no(spec[:forge_release]) ]
      end
      tables = []
      if platform_rows.any?
        tables << Table.new(title: "Platforms this CI builds", columns: [ "Platform", "Builder", "Exporter", "Helper steps", "Web shell", "Forge release" ],
                            rows: platform_rows)
      end
      Section.new(title: "CI", intro: intro, rows: rows, tables: tables)
    end

    def platforms
      built = WarpEngine.ci.platforms
      rows = WarpEngine::Platform.all.map do |platform|
        origin = if platform.legacy? then "host (legacy service)"
        elsif WarpEngine::Platform.registration(platform.name) then WarpEngine::Platform.builtin?(platform.name) ? "host (replaces built-in)" : "host"
        else "built-in"
        end
        [ platform.name, platform.label, origin, list(platform.expected_kinds), list(platform.required_kinds),
          built.key?(platform.name) ? list(platform.built_kinds) : "not built here", platform.release_rule || "marker decides" ]
      end
      Section.new(
        title: "Platforms",
        intro: "#{rows.size} platforms. A publish accepts the listed kinds and fails without a required one; the pipeline builds the rest it can.",
        rows: [],
        tables: [ Table.new(title: nil, columns: [ "Name", "Label", "From", "Accepts", "Requires", "Pipeline builds", "Releases from" ], rows: rows) ]
      )
    end

    def outlets
      begin
        all = WarpEngine::Outlets.validate!
        problem = nil
      rescue WarpEngine::ConfigurationError => e
        all = []
        problem = e.message
      end
      shelves = all.grep(WarpEngine::Outlets::Shelf).map(&:shelf)
      tables = [ Table.new(title: nil, columns: [ "Outlet", "Type", "Platforms" ],
                           rows: all.map { |outlet| [ outlet.key, outlet.type, list(outlet.platforms, "all") ] }) ]
      if shelves.any?
        tables << Table.new(
          title: "Shelves",
          columns: [ "Platform", "Folder", "Layout", "Kinds", "Names", "Statuses", "Preview", "Served at" ],
          rows: shelves.map do |shelf|
            names = shelf.folders? ? "folders of up to #{shelf.name_length}" : "#{shelf.name_length} characters, #{shelf.extension}"
            [ shelf.platform, shelf.directory, shelf.layout, list(shelf.kinds), names, list(shelf.listed_statuses),
              shelf.preview || "none", list(shelf.urls, "not published") ]
          end
        )
      end
      intro = problem ? "The outlet configuration is INVALID: #{problem}" : "Where the catalog leaves the engine; each is refreshed after a publish."
      Section.new(title: "Outlets", intro: intro, rows: [], tables: tables)
    end

    def admin_api
      api = config.admin_api
      return Section.new(title: "Admin API", intro: "Off.", rows: [], tables: []) unless api.enabled?

      limit = api.rate_limit ? "#{api.rate_limit[:to]} requests per #{duration(api.rate_limit[:within])}" : "none"
      Section.new(
        title: "Admin API",
        intro: "On, at #{WarpEngine::AdminApi.url_path}#{api.read_only? ? ', read-only' : ''}.",
        rows: [
          [ "Resources", api.resources == :all ? "all" : list(api.resources) ],
          [ "Tokens owned by", api.owner_class_name.presence || "anyone with an admin-scoped token" ],
          [ "Page size", "#{api.page_size}, at most #{api.max_page_size}" ],
          [ "Rate limit", limit ],
          [ "OpenAPI document", api.openapi_requires_auth? ? "needs a token" : "public" ],
          [ "Docs page", yes_no(api.docs_ui?, "served", "off") ],
          [ "MCP server", api.mcp? ? "on, without #{list(api.mcp_exclude)}" : "off" ]
        ],
        tables: []
      )
    end

    def extras
      resources = Array(config.additional_resources)
      Section.new(
        title: "Additional resources",
        intro: resources.any? ? "Host records edited on the engine's admin pages." : "None.",
        rows: [],
        tables: resources.any? ? [ Table.new(title: nil, columns: [ "On", "Association", "Label", "Several", "In the Admin API" ],
                                             rows: resources.map do |resource|
                                               [ resource.subject.to_s, resource.association.to_s, resource.label.to_s,
                                                 yes_no(resource.multiple), yes_no(resource.api?) ]
                                             end) ] : []
      )
    end
  end
end
