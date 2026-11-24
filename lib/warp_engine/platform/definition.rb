module WarpEngine
  class Platform
    # One asset kind a platform publishes.
    #
    # [kind]     the WarpEngine::AssetKind
    # [kind]     the WarpEngine::AssetKind
    # [ext]      the extension of a kind without a suffix (<tt>.prg</tt>), or
    #            the alternatives it may have, the preferred first
    #            (<tt>[".prg", ".d64"]</tt>): a release carries one of them
    # [required] a publish fails without it
    # [optional] the build checks do not miss it
    # [built]    the platform's pipeline produces it (else it is a manual upload)
    # [always]   the pipeline always produces it: its upload step fails without it
    KindSpec = ::Data.define(:kind, :ext, :required, :optional, :built, :always) do
      # Returns the kind name.
      def name = kind.name

      # Returns the extensions the kind may have, the preferred first; one
      # +nil+ for a kind with a suffix of its own.
      def extensions
        list = Array(ext).compact_blank
        list.empty? ? [ nil ] : list
      end

      # Returns the uploaded file name for +versioned+ (<tt>name-version</tt>)
      # with the preferred extension.
      def upload_name(versioned) = upload_names(versioned).first

      # Returns the uploaded file name for +versioned+ with each of the
      # #extensions, the preferred first.
      def upload_names(versioned) = extensions.map { |extension| kind.upload_name(versioned, ext: extension) }

      # Returns the name of the asset in the file container for +versioned+
      # with the preferred extension.
      def asset_name(versioned) = asset_names(versioned).first

      # Returns the asset names for +versioned+ with each of the #extensions.
      def asset_names(versioned) = extensions.map { |extension| kind.asset_name(versioned, ext: extension) }.uniq

      # Returns what follows <tt>name-version</tt> in the upload name, with the
      # preferred extension.
      def upload_suffix = upload_name("")

      # Returns what follows <tt>name-version</tt> in each upload name the
      # kind may have, the preferred first.
      def upload_suffixes = upload_names("")
    end

    # One key the CI marker of a platform may set (<tt>media: d64</tt>).
    #
    # [name]        the key
    # [values]      the values it takes
    # [description] what it changes, for the developer tools
    MarkerOption = ::Data.define(:name, :values, :description) do
      # Returns +true+ when +value+ is one of #values.
      def allows?(value) = values.include?(value.to_s)
    end

    # Everything the engine knows of a platform, built by a Builder.
    #
    # [name]           the platform name
    # [label]          the human-readable name
    # [kind_specs]     the KindSpec list
    # [metadata]       where a publish reads the software metadata: +:json+
    #                  (<tt>name-version.metadata.json</tt>), +:lua+ (the header
    #                  comments of <tt>name-version.lua</tt>) or a callable taking
    #                  the WarpEngine::Publish::Upload
    # [release_rule]   the CI release rule it forces (<tt>"tag"</tt>), or +nil+
    # [shelf_folder]   a callable <tt>(metadata, kind)</tt> returning the folder
    #                  spec of a +folders+ shelf, or +nil+
    # [ci_template]    the CI-neutral pipeline template: a builtin name or a path
    # [ci_variables]   extra variables the template sees
    # [version_source] the shell command that prints the version of the source
    # [version_file]   the file that command reads, for the tools that write the
    #                  version (a JSON file with a top-level +version+), or +nil+
    # [web_bindings]   the WebBinding list: the runtimes its releases play in
    # [variants]       the KindSpec list of each variant, by name (see
    #                  Builder#variant), the kinds every variant shares included;
    #                  empty for a platform without variants
    # [default_app]    the variant a software without an +app+ is, or +nil+
    # [app]            the variant this Definition describes (#variant), or +nil+
    # [options]        the MarkerOption list: the keys besides +platform+,
    #                  +name+, +release+ and +app+ the CI marker may set
    Definition = ::Data.define(:name, :label, :kind_specs, :metadata, :release_rule, :shelf_folder,
                               :ci_template, :ci_variables, :version_source, :web_bindings,
                               :version_file, :variants, :default_app, :app, :options) do
      # Builds a Definition; +web_bindings+, +variants+ and +options+ default
      # to none, +version_file+, +default_app+ and +app+ to +nil+.
      def initialize(web_bindings: [], version_file: nil, variants: {}, default_app: nil, app: nil, options: [], **attributes) = super

      # Returns the variant names, the default first; empty without variants.
      def apps = variants.keys

      # Returns +true+ when the platform has variants.
      def variants? = variants.any?

      # Returns the Definition of the variant +name+ (blank: the default one):
      # its kinds, and +app+ among the CI template variables. A platform
      # without variants returns itself for a blank +name+. Raises
      # ArgumentError for a variant the platform does not have.
      def variant(name)
        chosen = name.to_s.presence || default_app
        return self if chosen.nil? && !variants?
        raise ArgumentError, "platform #{self.name} has no app #{name}" unless variants.key?(chosen)

        with(kind_specs: variants.fetch(chosen), ci_variables: ci_variables.to_h.merge(app: chosen), app: chosen)
      end

      # Returns the names of every kind the platform publishes.
      def expected_kinds = kind_specs.map(&:name)

      # Returns the kinds a release must have.
      def required_kinds = kind_specs.select(&:required).map(&:name)

      # Returns the kinds a release may lack without counting as missing.
      def optional_kinds = kind_specs.select(&:optional).map(&:name)

      # Returns the kinds the platform's pipeline builds.
      def built_kinds = kind_specs.select(&:built).map(&:name)
    end

    # The platform DSL. WarpEngine::Platform.define (the builtin platforms) and
    # WarpEngine::Configuration#register_platform with a block (a host's own)
    # evaluate their block with it:
    #
    #   label "Amiga"
    #   kind :cartridge, ext: ".adf", required: true
    #   kinds :html, :win_x64
    #   kind :mac_arm64, built: false
    #   web :emulatorjs, core: "puae"
    #   ci template: Rails.root.join("ci/amiga.yaml.erb")
    #
    # A platform whose software comes in kinds of program that publish
    # different assets declares a #variant for each; the software's +app+
    # picks one (WarpEngine::Platform.for):
    #
    #   variant :cli, default: true do
    #     kind :cli_linux_x64, required: true
    #   end
    #   variant :gui do
    #     kind :linux_x64, required: true
    #   end
    class Builder
      # [name] the platform name
      def initialize(name)
        @name = name.to_s
        @label = @name.titleize
        @kind_specs = []
        @metadata = :json
        @ci = { template: @name, variables: {} }
        @web_bindings = []
        @variants = {}
        @options = []
      end

      # Sets the human-readable name (default: the titleized name).
      def label(value) = @label = value.to_s

      # Adds the asset kind +name+ (a WarpEngine::AssetKinds name).
      #
      # [ext]      the extension, for +cartridge+ and +source+, or a list of
      #            alternatives, the preferred first
      # [required] a publish fails without it (it is then also always built)
      # [optional] the build checks do not miss it
      # [built]    the pipeline builds it (default +true+)
      # [always]   the pipeline always builds it (default: +required+)
      def kind(name, ext: nil, required: false, optional: false, built: true, always: required)
        @kind_specs << KindSpec.new(kind: WarpEngine::AssetKinds.fetch(name), ext: ext, required: required,
                                    optional: optional, built: built, always: always)
      end

      # Adds each of +names+ with the defaults of #kind.
      def kinds(*names) = names.flatten.each { |name| kind(name) }

      # Declares the variant +name+: the #kind calls of the block are its own
      # kinds, next to the ones declared outside every variant. The first
      # variant, or the one with <tt>default: true</tt>, is the default.
      # Raises ArgumentError when the variant is declared twice.
      def variant(name, default: false, &block)
        key = name.to_s
        raise ArgumentError, "platform #{@name}: variant #{key} is declared twice" if @variants.key?(key)

        shared = @kind_specs
        @kind_specs = []
        instance_eval(&block)
        @variants[key] = @kind_specs
        @default_app = key if default || @default_app.nil?
      ensure
        @kind_specs = shared
      end

      # Declares the CI marker key +name+ taking one of +values+; a marker
      # value outside them does not reach the template. +description+ tells
      # the developer tools what it changes.
      def option(name, values:, description:)
        @options << MarkerOption.new(name: name.to_s, values: Array(values).map(&:to_s).freeze, description: description.to_s)
      end

      # Sets where the metadata is read: +:json+ (default), +:lua+ or a callable.
      def metadata(reader) = @metadata = reader

      # Forces the CI release rule (<tt>:tag</tt>).
      def release_rule(value) = @release_rule = value.to_s

      # Sets the callable that reads a +folders+ shelf's folder spec from the
      # release metadata.
      def shelf_folder(callable) = @shelf_folder = callable

      # Binds the platform to the runtime +runtime+ (see WebBinding): its
      # releases play in it on the web. Call it again for more runtimes; the
      # first binding, or the one with <tt>default: true</tt>, is the default.
      #
      # [as]       the binding key, needed when two bindings use one runtime
      # [payload]  the asset kind the runtime plays (default +:cartridge+)
      # [default]  makes this the default binding
      # [isolated] serves the page cross-origin isolated
      # [params]   the runtime parameters
      #
      # Raises ArgumentError when the key is taken.
      def web(runtime, **options)
        binding = WebBinding.build(runtime, **options)
        raise ArgumentError, "platform #{@name}: web binding #{binding.key} is declared twice" if @web_bindings.any? { |other| other.key == binding.key }

        @web_bindings << binding
      end

      # Sets the shell command that prints the version of the source, and the
      # +file+ it reads when that is a JSON file with a top-level +version+ (so
      # a tool releasing the software knows where to write the new version).
      def version_source(command, file: nil)
        @version_source = command.to_s
        @version_file = file&.to_s
      end

      # Sets the pipeline: the CI-neutral +template+ (a builtin name or a path;
      # default the platform name) and extra template +variables+.
      def ci(template: nil, **variables)
        @ci[:template] = template if template
        @ci[:variables] = variables
      end

      # Returns the Definition; with variants it describes the default one.
      def build
        variants = @variants.transform_values { |specs| (@kind_specs + specs).freeze }
        variants = variants.slice(@default_app).merge(variants).freeze
        base = Definition.new(name: @name, label: @label, kind_specs: @kind_specs.freeze, metadata: @metadata,
                              release_rule: @release_rule, shelf_folder: @shelf_folder, ci_template: @ci[:template],
                              ci_variables: @ci[:variables], version_source: @version_source, version_file: @version_file,
                              web_bindings: Platform.with_default(@web_bindings).freeze, variants: variants,
                              default_app: @default_app, options: @options.freeze)
        base.variants? ? base.variant(nil) : base
      end
    end
  end
end
