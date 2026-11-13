module WarpEngine
  class Platform
    # One asset kind a platform publishes.
    #
    # [kind]     the WarpEngine::AssetKind
    # [ext]      the extension of a kind without a suffix (<tt>.prg</tt>)
    # [required] a publish fails without it
    # [optional] the build checks do not miss it
    # [built]    the platform's pipeline produces it (else it is a manual upload)
    # [always]   the pipeline always produces it: its upload step fails without it
    KindSpec = ::Data.define(:kind, :ext, :required, :optional, :built, :always) do
      # Returns the kind name.
      def name = kind.name

      # Returns the uploaded file name for +versioned+ (<tt>name-version</tt>).
      def upload_name(versioned) = kind.upload_name(versioned, ext: ext)

      # Returns the name of the asset in the file container for +versioned+.
      def asset_name(versioned) = kind.asset_name(versioned, ext: ext)

      # Returns what follows <tt>name-version</tt> in the upload name.
      def upload_suffix = upload_name("")
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
    Definition = ::Data.define(:name, :label, :kind_specs, :metadata, :release_rule, :shelf_folder,
                               :ci_template, :ci_variables, :version_source) do
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
    #   ci template: Rails.root.join("ci/amiga.yaml.erb")
    class Builder
      # [name] the platform name
      def initialize(name)
        @name = name.to_s
        @label = @name.titleize
        @kind_specs = []
        @metadata = :json
        @ci = { template: @name, variables: {} }
      end

      # Sets the human-readable name (default: the titleized name).
      def label(value) = @label = value.to_s

      # Adds the asset kind +name+ (a WarpEngine::AssetKinds name).
      #
      # [ext]      the extension, for +cartridge+ and +source+
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

      # Sets where the metadata is read: +:json+ (default), +:lua+ or a callable.
      def metadata(reader) = @metadata = reader

      # Forces the CI release rule (<tt>:tag</tt>).
      def release_rule(value) = @release_rule = value.to_s

      # Sets the callable that reads a +folders+ shelf's folder spec from the
      # release metadata.
      def shelf_folder(callable) = @shelf_folder = callable

      # Sets the shell command that prints the version of the source.
      def version_source(command) = @version_source = command.to_s

      # Sets the pipeline: the CI-neutral +template+ (a builtin name or a path;
      # default the platform name) and extra template +variables+.
      def ci(template: nil, **variables)
        @ci[:template] = template if template
        @ci[:variables] = variables
      end

      # Returns the Definition.
      def build
        Definition.new(name: @name, label: @label, kind_specs: @kind_specs.freeze, metadata: @metadata,
                       release_rule: @release_rule, shelf_folder: @shelf_folder, ci_template: @ci[:template],
                       ci_variables: @ci[:variables], version_source: @version_source)
      end
    end
  end
end
