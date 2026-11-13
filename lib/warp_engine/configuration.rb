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
    # [device_code_ttl]               device code lifetime in seconds (default 600)
    # [device_code_interval]          minimum polling interval for device codes in seconds (default 5)
    # [ignored_user_agents]           user agent patterns (strings with <tt>*</tt> wildcards or regexps) the
    #                                 download statistics leave out (default empty)
    # [catalog_page_size]             catalog page size when the client names none (default 48)
    # [catalog_max_page_size]         the largest catalog page a client may ask for (default 200)
    # [additional_resources]          the WarpEngine::AdditionalResource list (default empty)
    # [shelves]                       the shelf definitions as hashes (see WarpEngine::Shelves; default empty)
    # [outlets]                       the other outlet definitions as hashes with +key+ and +type+ (see
    #                                 WarpEngine::Outlets; default empty)
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
                  :device_code_ttl,
                  :device_code_interval,
                  :ignored_user_agents,
                  :catalog_page_size,
                  :catalog_max_page_size,
                  :additional_resources,
                  :shelves,
                  :outlets,
                  :outlet_types

    # Replaces the WarpEngine::AdminApi::Configuration returned by #admin_api.
    attr_writer :admin_api

    # The registered non-builtin platforms: a Hash of name to
    # WarpEngine::Platform::Registration, filled by #register_platform.
    attr_reader :platforms

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
      @device_code_ttl               = 600
      @device_code_interval          = 5
      @ignored_user_agents           = []
      @catalog_page_size             = 48
      @catalog_max_page_size         = 200
      @additional_resources          = []
      @shelves                       = []
      @outlets                       = []
      @outlet_types                  = {}
      @platforms                     = {}
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
