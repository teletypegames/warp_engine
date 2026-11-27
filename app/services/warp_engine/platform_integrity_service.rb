module WarpEngine
  # Checks that every platform (WarpEngine::Platform) agrees with everything
  # that names it: its own definition, its CI template, its web runtimes, the
  # store engines, the directories, the host's CI and tooling settings and, unless
  # told not to, the catalog's records. Each problem is a Finding; an +error+
  # is something that breaks (a pipeline that does not render, a store that
  # cannot install, a software on an unknown platform), a +warning+ something
  # to look at. <tt>rake warp_engine:platforms:check</tt> prints the report.
  #
  #   WarpEngine::PlatformIntegrityService.new.check(data: false).findings.select(&:error?)
  class PlatformIntegrityService
    # One problem: the +platform+ it is about (<tt>"*"</tt> for one that is not
    # about a single platform), its +severity+ (+:error+ or +:warning+), a short
    # +code+ and a +message+ for a person.
    Finding = ::Data.define(:platform, :severity, :code, :message) do
      # Returns +true+ for an error.
      def error? = severity == :error

      # Returns the finding as a Hash with String keys, for JSON.
      def to_h = { "platform" => platform, "severity" => severity.to_s, "code" => code, "message" => message }
    end

    # What a check found: the +platforms+ it looked at and the +findings+.
    Report = ::Data.define(:platforms, :findings) do
      # Returns the errors.
      def errors = findings.select(&:error?)

      # Returns the warnings.
      def warnings = findings.reject(&:error?)

      # Returns +true+ when there is no error.
      def ok? = errors.empty?

      # Returns the findings about +platform+.
      def for(platform) = findings.select { |finding| finding.platform == platform.to_s }
    end

    # The marker keys the engine reads itself, which a platform's own option
    # must not take.
    RESERVED_OPTIONS = (%w[platform name release app] + [ WarpEngine::CI::PipelineConfig::DISABLE_OPTION ]).freeze

    # The CI adapters whose pipeline renderers every template is rendered with.
    RENDERERS = [ WarpEngine::CI::Woodpecker::PipelineConfig, WarpEngine::CI::Gitlab::PipelineConfig ].freeze

    # Checks the platforms named +names+ (every platform when +nil+). With
    # +data+ +false+ the catalog's records (softwares, release assets,
    # installed runtimes) are left alone, so it needs no database. Returns a
    # Report.
    def check(names: nil, data: true)
      platforms = names ? Array(names).map(&:to_s) : WarpEngine::Platform.names
      @findings = []
      unknown(platforms)
      known = platforms.select { |name| WarpEngine::Platform.exists?(name) }
      known.each { |name| check_platform(WarpEngine::Platform.find!(name), data: data) }
      check_names_of_disabling
      check_labels(known)
      check_store_engines(known)
      check_feeds(known)
      check_host(known)
      check_softwares(known) if data
      Report.new(known, @findings)
    end

    private

    def add(platform, severity, code, message)
      @findings << Finding.new(platform: platform.to_s, severity: severity, code: code, message: message)
    end

    def unknown(names)
      (names - WarpEngine::Platform.names).each { |name| add(name, :error, "unknown", "#{name} is not a platform") }
    end

    def check_platform(platform, data:)
      name = platform.name
      add(name, :error, "name", "the name does not match #{WarpEngine::CI::PipelineConfig::PLATFORM_FORMAT.inspect}") unless name.match?(WarpEngine::CI::PipelineConfig::PLATFORM_FORMAT)
      add(name, :warning, "label", "no label") if platform.label.blank?
      definition = platform.definition
      if definition.variants? && !definition.apps.include?(definition.default_app.to_s)
        add(name, :error, "default_app", "the default variant #{definition.default_app.inspect} is not one of #{definition.apps.join(', ')}")
      end
      variants(platform).each { |variant| check_kinds(variant) }
      check_options(platform)
      check_version(platform)
      check_web(platform, data: data)
      check_template(platform)
    end

    def variants(platform)
      platform.apps.empty? ? [ platform ] : platform.apps.map { |app| platform.for_app(app) }
    end

    def where(platform) = platform.app ? "#{platform.name} (app #{platform.app})" : platform.name

    def check_kinds(platform)
      specs = platform.kind_specs
      add(platform.name, :error, "no_required_kind", "#{where(platform)} requires no kind: a publish would take an empty release") if platform.required_kinds.empty?
      specs.each do |spec|
        if spec.kind.suffix.nil? && spec.extensions == [ nil ]
          add(platform.name, :error, "ext_missing", "#{where(platform)}: #{spec.name} has no extension, so its upload has no name")
        end
        Array(spec.ext).compact_blank.reject { |ext| ext.start_with?(".") }.each do |ext|
          add(platform.name, :warning, "ext_format", "#{where(platform)}: #{spec.name} extension #{ext.inspect} does not start with a dot")
        end
        if spec.required && !spec.built
          add(platform.name, :error, "required_not_built", "#{where(platform)}: #{spec.name} is required but its pipeline does not build it, so a CI publish always fails")
        end
        if spec.required && spec.optional
          add(platform.name, :warning, "required_optional", "#{where(platform)}: #{spec.name} is both required and optional")
        end
      end
    end

    def check_options(platform)
      platform.options.each do |option|
        if RESERVED_OPTIONS.include?(option.name)
          add(platform.name, :error, "option_reserved", "marker option #{option.name} is a key the engine reads itself")
        end
        add(platform.name, :error, "option_values", "marker option #{option.name} takes no value") if option.values.empty?
        option.values.reject { |value| value.match?(WarpEngine::CI::PipelineConfig::OPTION_FORMAT) }.each do |value|
          add(platform.name, :error, "option_value_format", "marker option #{option.name}: #{value.inspect} can never reach the template")
        end
      end
    end

    def check_version(platform)
      return unless platform.version_file.present? && platform.definition.version_source.blank?

      add(platform.name, :warning, "version_file", "names the version file #{platform.version_file} without a version source")
    end

    def check_web(platform, data:)
      platform.all_web_bindings.select(&:enabled).each do |binding|
        binding.errors.each { |error| add(platform.name, :error, "web_binding", "web binding #{binding.key}: #{error}") }
        unless platform.expected_kinds.include?(binding.payload)
          add(platform.name, :error, "web_payload", "web binding #{binding.key} plays #{binding.payload}, a kind the platform does not publish")
        end
        check_runtime(platform, binding) if data && binding.valid?
      end
    end

    def check_runtime(platform, binding)
      version = binding.runtime_object.current_version
      if version.nil?
        add(platform.name, :warning, "runtime_missing", "web binding #{binding.key}: runtime #{binding.runtime} has no installed version")
      elsif !WarpEngine::Publish::WebBinder.components_installed?(version, binding)
        add(platform.name, :warning, "runtime_component", "web binding #{binding.key}: #{version.label} lacks a component the binding needs")
      end
    end

    def check_template(platform)
      return if platform.legacy?

      template = platform.definition.ci_template.to_s
      path = Pathname.new(template).absolute? ? Pathname.new(template) : WarpEngine::CI::PipelineConfig::TEMPLATES_DIR.join("#{template}.yaml.erb")
      return add(platform.name, :error, "ci_template_missing", "CI template #{template} is not there (#{path})") unless path.file?

      cases(platform).each do |options|
        RENDERERS.each { |renderer| render(platform, renderer, options) }
      end
    end

    def cases(platform)
      apps = platform.apps.empty? ? [ nil ] : platform.apps
      apps.flat_map do |app|
        base = app ? { "app" => app } : {}
        variant = app ? platform.for_app(app) : platform
        disabled = variant.disableable_kinds
        [ base ] +
          platform.options.flat_map { |option| option.values.map { |value| base.merge(option.name => value) } } +
          (disabled.any? ? [ base.merge(WarpEngine::CI::PipelineConfig::DISABLE_OPTION => disabled.join(",")) ] : [])
      end
    end

    def render(platform, renderer, options)
      spec = { builder: "registry.example/builder:1", exporter: "registry.example/exporter:1" }
      yaml = renderer.new(platforms: { platform.name => spec }).render(platform: platform.name, name: "example", update_server: "https://example.org", options: options)
      return add(platform.name, :error, "ci_render", "#{renderer_name(renderer)} renders nothing#{case_text(options)}") if yaml.nil?

      YAML.safe_load(yaml)
    rescue ArgumentError, KeyError, NameError, TypeError, IndexError, Psych::Exception, ScriptError => e
      add(platform.name, :error, "ci_render", "#{renderer_name(renderer)} fails#{case_text(options)}: #{e.class}: #{e.message.lines.first&.strip}")
    end

    def renderer_name(renderer) = renderer.name.split("::")[-2]

    def case_text(options) = options.empty? ? "" : " with #{options.map { |key, value| "#{key}: #{value}" }.join(', ')}"

    def check_names_of_disabling
      clash = [ WarpEngine::Platform::WEB, WarpEngine::Platform::STORES ] & WarpEngine::AssetKinds.names
      clash.each { |name| add("*", :error, "disable_name", "#{name} is an asset kind and a disable name at once") }
    end

    def check_labels(names)
      names.map { |name| WarpEngine::Platform.find!(name) }.group_by(&:label).each do |label, platforms|
        next if label.blank? || platforms.size < 2

        add("*", :warning, "label_taken", "#{platforms.map(&:name).join(', ')} share the label #{label}")
      end
    end

    def check_store_engines(names)
      WarpEngine::Clients::ALL.each_value do |client|
        client.config_template.fetch("platforms", {}).each do |name, spec|
          next if WarpEngine::Platform.exists?(name) && !names.include?(name)

          check_store_platform(client, name, spec)
        end
      end
    end

    def check_store_platform(client, name, spec)
      return add(name, :error, "store_platform", "the #{client.label} store carries #{name}, which is not a platform") unless WarpEngine::Platform.exists?(name)

      platform = WarpEngine::Platform.find!(name)
      kinds = (spec["kind"].is_a?(Hash) ? spec["kind"].values : Array(spec["kind"])).flatten.map(&:to_s)
      kinds.reject { |kind| platform.expected_kinds.include?(kind) || variants(platform).any? { |variant| variant.expected_kinds.include?(kind) } }.each do |kind|
        add(name, :error, "store_kind", "the #{client.label} store installs #{kind}, a kind the platform does not publish")
      end
      check_store_ext(client, platform, spec, kinds)
      return unless spec.key?("core") && platform.libretro.nil?

      add(name, :error, "store_core", "the #{client.label} store runs it in a libretro core, but the platform declares none")
    end

    def check_store_ext(client, platform, spec, kinds)
      ext = spec["ext"]
      return unless ext.is_a?(String) && ext.present?

      allowed = kinds.flat_map { |kind| platform.kind_specs.select { |s| s.name == kind }.flat_map(&:extensions) }.compact
      return if allowed.empty? || allowed.include?(ext)

      add(platform.name, :warning, "store_ext", "the #{client.label} store takes only #{ext}, the platform publishes #{allowed.join(', ')}")
    end

    def check_feeds(names)
      feeds = WarpEngine::Feeds.validate!
      feeds.each do |feed|
        next unless feed.respond_to?(:kinds)

        feed.platforms.each do |name|
          next unless names.include?(name)

          platform = WarpEngine::Platform.find!(name)
          published = variants(platform).flat_map(&:expected_kinds)
          (feed.kinds - published).each do |kind|
            add(name, :error, "feed_kind", "feed #{feed.key} carries #{kind}, a kind the platform does not publish")
          end
        end
      end
    rescue WarpEngine::ConfigurationError => e
      add("*", :error, "feeds", e.message)
    end

    def check_host(names)
      configured = WarpEngine.ci.configured? ? WarpEngine.ci.platforms.to_h.transform_keys(&:to_s) : nil
      if configured
        (configured.keys - WarpEngine::Platform.names).each { |name| add(name, :error, "ci_unknown", "the CI settings name #{name}, which is not a platform") }
        names.each { |name| check_ci_spec(WarpEngine::Platform.find!(name), configured[name]) }
      end
      { "platform_tooling" => WarpEngine.config.platform_toolings, "platform_web" => WarpEngine.config.platform_web_changes }.each do |setting, by_platform|
        (by_platform.keys.map(&:to_s) - WarpEngine::Platform.names).each do |name|
          add(name, :error, "#{setting}_unknown", "#{setting} names #{name}, which is not a platform")
        end
      end
    end

    def check_ci_spec(platform, spec)
      return add(platform.name, :warning, "ci_not_configured", "the CI does not build it here (no builder in the CI settings)") if spec.nil?

      spec = spec.to_h.symbolize_keys
      add(platform.name, :error, "ci_builder", "the CI settings give it no builder image") if spec[:builder].blank?
      return if platform.legacy? || spec[:exporter].present?

      template = platform.definition.ci_template.to_s
      path = Pathname.new(template).absolute? ? Pathname.new(template) : WarpEngine::CI::PipelineConfig::TEMPLATES_DIR.join("#{template}.yaml.erb")
      return unless path.file? && path.read.include?("exporter")

      add(platform.name, :error, "ci_exporter", "its template runs a step in the exporter image, which the CI settings do not give")
    end

    def check_softwares(names)
      WarpEngine::Software.kept.where.not(platform: WarpEngine::Platform.names).group(:platform).count.each do |name, count|
        add(name.to_s, :error, "software_platform", "#{count} software#{'s' unless count == 1} on #{name.inspect}, which is not a platform")
      end
      WarpEngine::Software.kept.where(platform: names).find_each do |software|
        software.valid?
        messages = %i[app disabled_kinds].flat_map { |attribute| software.errors.full_messages_for(attribute) }
        messages.each { |message| add(software.platform, :error, "software_invalid", "#{software.name}: #{message}") }
        check_assets(software)
      end
    end

    def check_assets(software)
      platform = WarpEngine::Platform.find(software.platform, app: software.app)
      return if platform.nil?

      unexpected = WarpEngine::ReleaseAsset.kept.joins(:release).merge(WarpEngine::Release.kept)
                                           .where(releases: { software_id: software.id }).where.not(kind: platform.definition.expected_kinds).distinct.pluck(:kind)
      return if unexpected.empty?

      add(software.platform, :warning, "unexpected_assets", "#{software.name} has #{unexpected.join(', ')} assets, kinds #{platform.label} does not publish")
    end
  end
end
