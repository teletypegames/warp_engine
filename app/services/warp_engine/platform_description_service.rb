module WarpEngine
  # Describes the platforms to the tools a developer works with (an editor
  # extension, a scaffolder): what a platform publishes, where its metadata
  # comes from, how it plays on the web, which pipeline marker builds it, the
  # host's tooling for it, and the JSON Schema of its metadata.
  class PlatformDescriptionService
    # The JSON Schema dialect of #metadata_schema.
    SCHEMA_DIALECT = "https://json-schema.org/draft/2020-12/schema".freeze

    # The form of a version the editor accepts: dotted numbers with an
    # optional pre-release or build suffix.
    VERSION_PATTERN = '^[0-9]+(\.[0-9]+){0,3}([-+][0-9A-Za-z.-]+)?$'.freeze

    # The form of a +license+: an SPDX licence id or expression (<tt>MIT</tt>,
    # <tt>GPL-3.0-or-later</tt>, <tt>MIT OR Apache-2.0</tt>), not a name
    # like <tt>MIT License</tt>.
    LICENSE_PATTERN = "^[A-Za-z0-9.+-]+( (AND|OR|WITH) [A-Za-z0-9.+-]+)*$".freeze

    # The marker keys every platform takes, with what they change.
    COMMON_OPTIONS = [
      { "name" => "release", "values" => WarpEngine::CI::PipelineConfig::RELEASE_RULES,
        "description" => "tag (default): a new version is released by the tag the pipeline sets; push: every push to the default branch releases" }
    ].freeze

    # The longest +shelf_name+ (WarpEngine::Software validates it too).
    SHELF_NAME_LENGTH = 32

    # The longest +category+ key (WarpEngine::Software validates it too).
    CATEGORY_LENGTH = 64

    # The marker file of each CI adapter, by WarpEngine::CI adapter name.
    MARKER_FILES = { "Woodpecker" => ".woodpecker.yaml", "GitLab" => ".gitlab-ci.yml" }.freeze

    # [ci] the CI adapter whose builder images and marker are described
    #      (default: WarpEngine.ci)
    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    # Returns the description of every platform (#describe), in the order of
    # WarpEngine::Platform.names.
    def all = WarpEngine::Platform.all.map { |platform| describe(platform) }

    # Returns the description of the platform named +name+, or +nil+ when there
    # is none.
    def find(name)
      platform = WarpEngine::Platform.find(name)
      platform && describe(platform)
    end

    # Returns the description of +platform+ (a WarpEngine::Platform) as a Hash
    # with String keys:
    #
    # [name, label]    the platform's names
    # [kinds]          each KindSpec of the default variant: +name+, +upload+ (the upload name with
    #                  <tt>NAME-VERSION</tt> and the preferred extension), +uploads+
    #                  (every upload name it may have, the preferred first), +required+, +optional+, +built+, +always+
    # [metadata]       +format+ (+json+, +lua+ or +custom+), +file+ (the file a
    #                  developer edits, or +nil+) and +keys+
    # [version]        +source+: +metadata+ (the +version+ of metadata.json) or
    #                  +command+, with the +command+ when it is one and the
    #                  +file+ it reads (a JSON file with a top-level +version+) or +nil+
    # [apps]           the variants (empty without): +name+, +default+, +marker+
    #                  (the marker line that picks it) and +kinds+ as above
    # [options]        the CI marker keys besides +platform+ and +name+:
    #                  +name+, +values+ and +description+ (+release+ unless the
    #                  platform forces it, +app+ with variants, then the
    #                  platform's own WarpEngine::Platform::MarkerOption list)
    # [releaseRule]    the forced CI release rule (+tag+), or +nil+
    # [libretro]       the libretro core its releases run on, +key+, +file+
    #                  and +name+, or +nil+
    # [web]            the enabled web bindings: +key+, +runtime+, +label+,
    #                  +payload+, +default+, +params+ (the runtime's parameter names
    #                  and types)
    # [ci]             +adapter+, +marker+ (file and content), +builder+ image,
    #                  +served+ (whether the adapter builds the platform)
    # [tooling]        what the host set with WarpEngine::Configuration#platform_tooling
    def describe(platform)
      {
        "name" => platform.name,
        "label" => platform.label,
        "kinds" => platform.kind_specs.map { |spec| kind(spec, platform) },
        "apps" => apps(platform),
        "options" => options(platform),
        "metadata" => metadata(platform),
        "version" => version(platform),
        "releaseRule" => platform.release_rule,
        "libretro" => platform.libretro&.then { |core| { "key" => core.key, "file" => core.file, "name" => core.name } },
        "web" => platform.web_bindings.map { |binding| web_binding(binding) },
        "ci" => ci(platform),
        "tooling" => WarpEngine.config.platform_toolings.fetch(platform.name, {}).deep_stringify_keys
      }
    end

    # Returns the JSON Schema (SCHEMA_DIALECT) of the metadata of the platform
    # named +name+ as a Hash, or +nil+ when there is none. It holds every key a
    # publish reads (WarpEngine::Publish::MetadataReader::KEYS), +version+ when
    # the version comes from the metadata, the known categories as examples,
    # and the +web+ section with the platform's binding keys and their runtime
    # parameters.
    def metadata_schema(name)
      platform = WarpEngine::Platform.find(name)
      return nil if platform.nil?

      properties = {
        "name" => { "type" => "string", "minLength" => 1, "description" => "The software name, unique in the catalog; uploads are NAME-VERSION" },
        "title" => { "type" => "string", "minLength" => 1, "description" => "The title the catalog shows" },
        "author" => { "type" => "string" },
        "desc" => { "type" => "string", "description" => "The description the catalog shows" },
        "site" => { "type" => "string", "format" => "uri", "description" => "Becomes the \"#{Publish::Recorder::SITE_LABEL}\" link" },
        "repo" => { "type" => "string", "description" => "The git repository: becomes the \"#{Publish::Recorder::REPO_LABEL}\" source link" },
        "forks_allowed" => { "type" => "boolean", "description" => "Whether the developer tools may offer a fork (default true)" },
        "fork_of_engine" => { "type" => "string", "format" => "uri", "description" => "For a fork: the parent engine's base URL" },
        "fork_of_name" => { "type" => "string", "description" => "For a fork: the parent's name on its engine" },
        "fork_of_version" => { "type" => "string", "description" => "For a fork: the parent release it was forked from" },
        "fork_of_repo" => { "type" => "string", "description" => "For a fork: the parent's repository it was forked from" },
        "license" => { "type" => "string", "pattern" => LICENSE_PATTERN, "description" => "An SPDX licence id, e.g. MIT" },
        "category" => { "type" => "string", "maxLength" => CATEGORY_LENGTH, "examples" => categories,
                        "description" => "A category key; a new key is registered for review" },
        "shelf_name" => { "type" => "string", "maxLength" => SHELF_NAME_LENGTH, "pattern" => "^[A-Za-z0-9-]+$",
                          "description" => "The name on the platform's shelves; upcased on save" },
        "web" => web_schema(platform)
      }
      required = %w[name title]
      if platform.version_source.nil?
        properties["version"] = { "type" => "string", "pattern" => VERSION_PATTERN,
                                  "description" => "The version the pipeline builds; a version tag must match it" }
        required << "version"
      end

      {
        "$schema" => SCHEMA_DIALECT,
        "title" => "#{platform.label} metadata",
        "type" => "object",
        "properties" => properties,
        "required" => required
      }
    end

    private

    def kind(spec, platform)
      { "name" => spec.name, "upload" => spec.upload_name("NAME-VERSION"), "uploads" => spec.upload_names("NAME-VERSION"),
        "required" => spec.required, "optional" => spec.optional, "built" => platform.built_kinds.include?(spec.name), "always" => spec.always }
    end

    def apps(platform)
      platform.apps.map do |name|
        variant = platform.for_app(name)
        { "name" => name, "default" => name == platform.apps.first, "marker" => "app: #{name}",
          "kinds" => variant.kind_specs.map { |spec| kind(spec, variant) } }
      end
    end

    def options(platform)
      common = platform.release_rule ? [] : COMMON_OPTIONS
      app = if platform.apps.any?
        [ { "name" => "app", "values" => platform.apps, "description" => "The kind of program; #{platform.apps.first} when missing" } ]
      else
        []
      end
      disable = if platform.disableable_kinds.any?
        [ { "name" => WarpEngine::CI::PipelineConfig::DISABLE_OPTION, "values" => platform.disableable_kinds,
            "description" => "The kinds the software turns off, separated by spaces: not built, not uploaded, left out of the catalog; web: no web play" } ]
      else
        []
      end
      common + app + disable + platform.options.map { |option| { "name" => option.name, "values" => option.values, "description" => option.description } }
    end

    def metadata(platform)
      reader = platform.definition.metadata
      format = %w[json lua].include?(reader.to_s) ? reader.to_s : "custom"
      file = { "json" => "metadata.json" }[format]
      { "format" => format, "file" => file, "keys" => Publish::MetadataReader::KEYS.map(&:to_s) }
    end

    def version(platform)
      command = platform.version_source
      return { "source" => "metadata", "command" => nil, "file" => nil } unless command

      { "source" => "command", "command" => command, "file" => platform.version_file }
    end

    def web_binding(binding)
      runtime = binding.runtime_object
      params = runtime ? runtime.definition.params.values.map { |param| { "name" => param.name.to_s, "type" => param.type.to_s } } : []
      { "key" => binding.key, "runtime" => binding.runtime, "label" => runtime&.definition&.label,
        "payload" => binding.payload, "default" => binding.default, "params" => params }
    end

    def ci(platform)
      spec = @ci.platforms.to_h.transform_keys(&:to_s)[platform.name]
      marker_file = MARKER_FILES[@ci.name]
      { "adapter" => @ci.name, "served" => !spec.nil?,
        "marker" => marker_file && { "file" => marker_file, "content" => "platform: #{platform.name}\n" },
        "builder" => spec&.dig(:builder) }
    end

    def web_schema(platform)
      bindings = platform.web_bindings
      params = bindings.flat_map { |binding| binding.runtime_object&.definition&.params&.values.to_a }.uniq(&:name)
      {
        "type" => "object",
        "description" => "How the release plays on the web",
        "properties" => {
          "enabled" => { "type" => "boolean", "description" => "false turns web play off for the release" },
          "runtime" => { "type" => "string", "enum" => bindings.map(&:key),
                         "description" => "The binding to play in; the platform's default when missing" },
          "params" => { "type" => "object", "properties" => params.to_h { |param| [ param.name.to_s, param_schema(param) ] },
                        "additionalProperties" => false },
          "start" => { "type" => "string", "description" => "The program a launcher starts" }
        },
        "additionalProperties" => false
      }
    end

    def param_schema(param)
      { "type" => { hash: "object", boolean: "boolean" }.fetch(param.type, "string") }
    end

    def categories = WarpEngine::SoftwareCategory.ordered.pluck(:key)
  end
end
