module WarpEngine
  # The engine's settings, held once per process in WarpEngine.config and
  # written by WarpEngine.configure (directly or through
  # WarpEngine::Configuration::DSL). Every attribute has a working default.
  class Configuration
    # The plain settings, each readable and writable:
    #
    # [site_url]                      base URL of the host site; the admin links a software to its public page
    #                                 from here (default +nil+: no link)
    # [file_container_path]           directory the build artifacts live under (default
    #                                 <tt>ENV["FILE_CONTAINER_PATH"]</tt> or <tt>/softwares</tt>)
    # [update_secret]                 shared secret for the <tt>/build/*</tt> endpoints (default
    #                                 <tt>ENV["UPDATE_SECRET"]</tt>; +nil+ rejects every request)
    # [application_token_source]      +:env+ (the shared secret) or +:database+ (WarpEngine::ApplicationToken
    #                                 records) as the <tt>/build/*</tt> authentication (default +:env+)
    # [application_token_owner_class] class name of the owner every database application token belongs to
    # [max_upload_size]               upload size cap in bytes (default 500 MB)
    # [enforce_software_ownership]    when +true+, a database token may only upload or publish softwares of its
    #                                 own owner (default +false+)
    # [ci_adapter]                    the CI adapter: +:woodpecker+ (default, from ENV), +:gitlab+, +:none+ or
    #                                 an adapter object (see WarpEngine::CI.adapter)
    # [image_class_name]              class name of the host's image model (default <tt>"Image"</tt>)
    # [image_adapter]                 the image adapter; +nil+ uses WarpEngine::Images::HostModel
    # [storage_adapter]               the storage adapter: +:local+ (default) or an adapter object
    # [access_policy]                 the access policy: +:open+ (default) or a policy object
    # [access_token_owner_class]      class name of the client sign-in subject; +nil+ (default) disables sign-in
    # [subject_resolver]              callable taking the request and returning the session subject, or +nil+
    # [identity_verification_url]     the page a user approves a device code on
    # [tool_verification_url]         the page an administrator approves a tool's
    #                                 device code on (default: the admin's tool sign-in)
    # [device_code_ttl]               device code lifetime in seconds (default 600)
    # [device_code_interval]          minimum polling interval for device codes in seconds (default 5)
    # [ignored_user_agents]           user agent patterns (strings with <tt>*</tt> wildcards or regexps) the
    #                                 download statistics leave out (default empty)
    # [catalog_page_size]             catalog page size when the client names none (default 48)
    # [catalog_max_page_size]         the largest catalog page a client may ask for (default 200)
    # [sys_info_live_checks]          whether the SysInfo page may call the CI server (default +true+; +false+
    #                                 turns the live checks off for good)
    # [additional_resources]          the WarpEngine::AdditionalResource list (default empty)
    # [outlets]                       the outlet definitions, shelves among them, as hashes with +key+,
    #                                 +type+ and the type's options (see WarpEngine::Outlets; default empty)
    # [outlet_types]                  the outlet types the host registered: a Hash of type name to class name
    #                                 (default empty)
    attr_accessor :site_url,
                  :file_container_path,
                  :update_secret,
                  :application_token_source,
                  :application_token_owner_class,
                  :max_upload_size,
                  :enforce_software_ownership,
                  :ci_adapter,
                  :image_class_name,
                  :image_adapter,
                  :storage_adapter,
                  :access_policy,
                  :access_token_owner_class,
                  :subject_resolver,
                  :identity_verification_url,
                  :tool_verification_url,
                  :device_code_ttl,
                  :device_code_interval,
                  :ignored_user_agents,
                  :catalog_page_size,
                  :catalog_max_page_size,
                  :sys_info_live_checks,
                  :additional_resources,
                  :outlets,
                  :outlet_types

    # Replaces the WarpEngine::AdminApi::Configuration returned by #admin_api.
    attr_writer :admin_api

    # The registered non-builtin platforms: a Hash of name to
    # WarpEngine::Platform::Registration, filled by #register_platform.
    attr_reader :platforms

    # The runtimes the host registered: a Hash of name to
    # WarpEngine::Runtime::Definition, filled by #register_runtime.
    attr_reader :runtimes

    # The runtime versions the host chose: a Hash of runtime name to version,
    # filled by #runtime. A runtime without an entry uses its newest version.
    attr_reader :runtime_versions

    # The host's changes to the platforms' web bindings: a Hash of platform
    # name to a list of option Hashes, filled by #platform_web.
    attr_reader :platform_web_changes

    # The host's tooling of the platforms for the developer tools: a Hash of
    # platform name to a Hash of values, filled by #platform_tooling.
    attr_reader :platform_toolings

    # Creates a configuration with every setting at its default.
    def initialize
      @site_url                      = nil
      @file_container_path           = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
      @update_secret                 = ENV["UPDATE_SECRET"]
      @application_token_source      = :env
      @application_token_owner_class = nil
      @max_upload_size               = 500 * 1024 * 1024
      @enforce_software_ownership    = false
      @ci_adapter                    = :woodpecker
      @image_class_name              = "Image"
      @image_adapter                 = nil
      @storage_adapter               = :local
      @access_policy                 = :open
      @access_token_owner_class      = nil
      @subject_resolver              = nil
      @identity_verification_url     = nil
      @tool_verification_url         = nil
      @device_code_ttl               = 600
      @device_code_interval          = 5
      @ignored_user_agents           = []
      @catalog_page_size             = 48
      @catalog_max_page_size         = 200
      @sys_info_live_checks          = true
      @additional_resources          = []
      @outlets                       = []
      @outlet_types                  = {}
      @platforms                     = {}
      @runtimes                      = {}
      @runtime_versions              = {}
      @platform_web_changes          = {}
      @platform_toolings             = {}
    end

    # Registers (or replaces) a platform the engine does not ship. With a block,
    # the block is the WarpEngine::Platform::Builder DSL, the same the builtin
    # platforms are declared with:
    #
    #   config.register_platform "amiga" do
    #     label "Amiga"
    #     kind :cartridge, ext: ".adf", required: true
    #     ci template: Rails.root.join("ci/amiga.yaml.erb")
    #   end
    #
    # Without a block (deprecated, the pre-1.12 form) +service+ names a class
    # built from WarpEngine::Platforms::Updatable.
    #
    # [name]           the platform name; must match WarpEngine::Platform::FORMAT
    # [service]        legacy: class (or class name) of the platform service
    # [built_kinds]    legacy: the asset kinds the platform's CI pipeline builds
    # [templates]      legacy: CI pipeline templates as a Hash of adapter name to template path
    # [version_source] shell command printing the source version in CI, or +nil+ for the default
    #
    # Returns the stored WarpEngine::Platform::Definition (or legacy
    # WarpEngine::Platform::Registration). Raises ArgumentError when the name is
    # malformed, or when neither a block nor a +service+ is given.
    def register_platform(name, service: nil, built_kinds: [], templates: {}, version_source: nil, &block)
      name = name.to_s
      raise ArgumentError, "platform name #{name.inspect} must match #{Platform::FORMAT.inspect}" unless name.match?(Platform::FORMAT)
      raise ArgumentError, "register_platform #{name.inspect} needs a block (or a legacy service:)" unless block || service

      @platforms[name] = block ? platform_definition(name, version_source, &block) : Platform::Registration.new(
        name:           name,
        service:        service.to_s,
        built_kinds:    Array(built_kinds).map(&:to_s),
        templates:      templates.to_h.to_h { |adapter, path| [ adapter.to_sym, Pathname.new(path.to_s) ] },
        version_source: version_source&.to_s
      )
    end

    # Registers (or replaces) a runtime the engine does not ship; the block is
    # the WarpEngine::Runtime::Builder DSL:
    #
    #   config.register_runtime "ruffle" do
    #     label "Ruffle"
    #     source :upload
    #     files "ruffle.js", "*.wasm"
    #     template Rails.root.join("runtimes/ruffle.html")
    #   end
    #
    # Returns the WarpEngine::Runtime::Definition. Raises ArgumentError for a
    # malformed name or definition.
    def register_runtime(name, &block)
      builder = Runtime::Builder.new(name)
      builder.instance_eval(&block) if block
      @runtimes[name.to_s] = builder.build
    end

    # Chooses the version +version+ of the runtime +name+ for the new
    # releases; see WarpEngine::Runtime#chosen_version. Returns the version.
    def runtime(name, version:)
      @runtime_versions[name.to_s] = version.to_s
    end

    # Changes the web bindings of the platform +platform+: a binding keyed
    # +as+ (default: +runtime+) that exists gets the +options+ merged in (a
    # WarpEngine::Platform::WebBinding attribute or a runtime parameter),
    # otherwise a new binding to +runtime+ is added. Calling it again for
    # the same key replaces the earlier change.
    #
    #   config.platform_web :c64, :emulatorjs, as: :fast, core: "vice_x64"   # adds a binding
    #   config.platform_web :c64, :fast, default: true                       # makes it the default
    #   config.platform_web :c64, :emulatorjs, enabled: false                # switches one off
    #
    # Returns the platform's change list.
    def platform_web(platform, runtime, **options)
      change = { runtime: runtime.to_s, **options }
      key = (change[:as] || change[:runtime]).to_s
      list = @platform_web_changes.fetch(platform.to_s, []).reject { |other| (other[:as] || other[:runtime]).to_s == key }
      @platform_web_changes[platform.to_s] = list + [ change ]
    end

    # Sets what the developer tools get to know of the platform +platform+
    # besides its definition: free-form +values+ the host chooses (where the
    # project template is, a demo, documentation links), served by
    # <tt>GET /build/platforms</tt> under +tooling+. Calling it again merges
    # into the earlier values.
    #
    #   config.platform_tooling :c64, template: "https://git.example/build/c64-tools",
    #                                 docs: "https://wiki.example/c64"
    #
    # Returns the platform's tooling Hash.
    def platform_tooling(platform, **values)
      @platform_toolings[platform.to_s] = @platform_toolings.fetch(platform.to_s, {}).merge(values)
    end

    # Returns the WarpEngine::AdminApi::Configuration, creating it with its
    # defaults on first use.
    def admin_api
      @admin_api ||= AdminApi::Configuration.new
    end

    # Returns +true+ when the user agent string +ua+ matches one of
    # #ignored_user_agents (wildcard strings match case-insensitively and in
    # full); +false+ for a blank +ua+.
    def ignored_user_agent?(ua)
      return false if ua.blank?

      @_ignored_ua_patterns ||= Array(@ignored_user_agents).map do |pattern|
        pattern.is_a?(Regexp) ? pattern : Regexp.new("\\A#{Regexp.escape(pattern).gsub("\\*", ".*")}\\z", Regexp::IGNORECASE)
      end

      @_ignored_ua_patterns.any? { |re| re.match?(ua) }
    end

    # Sets the ignored user agent patterns and drops the compiled pattern cache.
    def ignored_user_agents=(value)
      @ignored_user_agents = value
      @_ignored_ua_patterns = nil
    end

    private

    def platform_definition(name, version_source, &block)
      builder = Platform::Builder.new(name)
      builder.version_source(version_source) if version_source
      builder.instance_eval(&block)
      builder.build
    end
  end
end

require "warp_engine/configuration/dsl"
