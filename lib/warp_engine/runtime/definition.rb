module WarpEngine
  class Runtime
    # A parameter a platform binding passes to the runtime's page.
    #
    # [name]      the parameter name, a Symbol
    # [type]      +:string+ (default), +:hash+ or +:boolean+
    # [required]  a binding without it is invalid
    # [component] the component kind its value names (e.g. +:core+), or +nil+
    # [default]   the value when neither the binding nor the release sets it
    Param = ::Data.define(:name, :type, :required, :component, :default) do
      # Returns +true+ when +value+ fits the type (+nil+ always does).
      def accepts?(value)
        return true if value.nil?

        case type
        when :hash then value.is_a?(Hash)
        when :boolean then [ true, false ].include?(value)
        else value.is_a?(String) || value.is_a?(Symbol)
        end
      end
    end

    # A kind of installable part of a runtime, e.g. a core of EmulatorJS. Its
    # +patterns+ are file globs relative to the runtime directory with
    # <tt>%{key}</tt> for the component key; the files of a component are
    # those of the version's checksum list that match them.
    Component = ::Data.define(:kind, :patterns) do
      # Returns the files of +checksums+ (a Hash of file to SHA-256) that
      # belong to the component +key+.
      def files(key, checksums)
        globs = patterns.map { |pattern| format(pattern, key: key) }
        checksums.keys.select { |file| globs.any? { |glob| File.fnmatch?(glob, file, File::FNM_PATHNAME) } }
      end
    end

    # One version of a downloaded runtime: its +source+ URL prefix (each file
    # is fetched from <tt>source + file</tt>) and its +checksums+ (a Hash of
    # file, relative to the runtime directory, to SHA-256 hex digest).
    Version = ::Data.define(:version, :source, :checksums)

    # Everything the engine knows of a runtime, built by a Builder.
    #
    # [name]       the runtime name
    # [label]      the human-readable name
    # [license]    the licence of its files (an SPDX id)
    # [source]     +:download+ or +:upload+
    # [versions]   the Version list of a downloaded runtime, keyed by version, oldest first
    # [files]      the base files every version has (globs for an uploaded runtime too)
    # [components] the Component list, keyed by kind
    # [params]     the Param list, keyed by name
    # [template]   the path of the page template
    # [notice]     the path of the licence notice installed beside the files
    #              as WarpEngine::Runtime::NOTICE, or +nil+
    # [controls]   the Proc that turns the resolved parameters into
    #              WarpEngine::Runtime::Controls rows, or +nil+
    Definition = ::Data.define(:name, :label, :license, :source, :versions, :files, :components, :params, :template,
                               :notice, :controls) do
      # Returns +true+ when the files are downloaded from a pinned source.
      def download? = source == :download

      # Returns +true+ when a build uploads the files.
      def upload? = source == :upload

      # Returns the page template as a String.
      def template_source = File.read(template)

      # Returns the base files of the version +version+: every checksum entry
      # that is not a component's file. For an uploaded runtime, the declared
      # file list.
      def base_files(version = nil)
        return files if upload? || versions[version.to_s].nil?

        checksums = versions[version.to_s].checksums
        checksums.keys - components.values.flat_map { |component| component.files("*", checksums) }
      end

      # Returns the parameter values for the page: each Param's default,
      # overridden by +layers+ (Hashes, later ones win; only known parameters
      # are taken), as a Hash with String keys. A Hash value is merged one
      # level deep, so a release can add one option to a binding's options.
      def resolve_params(*layers)
        params.each_value.with_object({}) do |param, values|
          value = param.default
          layers.each do |layer|
            next unless layer.respond_to?(:key?)

            key = [ param.name, param.name.to_s ].find { |candidate| layer.key?(candidate) }
            next unless key

            value = value.is_a?(Hash) && layer[key].is_a?(Hash) ? value.merge(layer[key]) : layer[key]
          end
          values[param.name.to_s] = value.is_a?(Hash) ? value.deep_stringify_keys : value
        end
      end

      # Returns the WarpEngine::Runtime::Controls rows the runtime generates
      # from +params+ (resolved parameters, see #resolve_params); empty when it
      # generates none.
      def controls_for(params) = controls ? Controls.normalize(controls.call(params.to_h)) : []

      # Returns the errors of the binding parameters +params+ (a Hash), as an
      # Array of messages; empty when they fit.
      def param_errors(params)
        given = params.to_h.transform_keys(&:to_sym)
        errors = (given.keys - self.params.keys).map { |key| "unknown parameter #{key}" }
        self.params.each_value do |param|
          value = given[param.name]
          errors << "#{param.name} is required" if param.required && value.blank?
          errors << "#{param.name} must be a #{param.type}" unless param.accepts?(value)
        end
        errors
      end
    end

    # The runtime DSL. WarpEngine::Runtime.define (the builtin runtimes) and
    # WarpEngine::Configuration#register_runtime (a host's own) evaluate their
    # block with it:
    #
    #   label "EmulatorJS"
    #   license "GPL-3.0-only"
    #   version "4.2.3", source: "https://cdn.emulatorjs.org/4.2.3/data/"
    #   component :core, "cores/%{key}-*wasm.data", "cores/reports/%{key}.json"
    #   param :core, required: true, component: :core
    #   template "emulatorjs.html"
    #
    # A downloaded runtime takes its file list from the checksum file of each
    # version: <tt>lib/warp_engine/runtime/checksums/<name>-<version>.sha256</tt>
    # for a builtin one (the format of +sha256sum+), or the +checksums+ path a
    # host gives.
    class Builder
      # The directory of the builtin page templates.
      TEMPLATES = File.expand_path("templates", __dir__)

      # The directory of the builtin checksum files.
      CHECKSUMS = File.expand_path("checksums", __dir__)

      # The directory of the builtin licence notices.
      NOTICES = File.expand_path("notices", __dir__)

      # [name] the runtime name; must match WarpEngine::Runtime::FORMAT.
      # Raises ArgumentError when it does not.
      def initialize(name)
        @name = name.to_s
        raise ArgumentError, "runtime name #{@name.inspect} must match #{FORMAT.inspect}" unless @name.match?(FORMAT)

        @label = @name.titleize
        @source = :download
        @versions = {}
        @files = []
        @components = {}
        @params = {}
        @template = File.join(TEMPLATES, "#{@name}.html")
        @controls = nil
        builtin_notice = File.join(NOTICES, "#{@name}.txt")
        @notice = builtin_notice if File.file?(builtin_notice)
      end

      # Sets the human-readable name (default: the titleized name).
      def label(value) = @label = value.to_s

      # Sets the licence of the files (an SPDX id).
      def license(value) = @license = value.to_s

      # Declares that a build uploads the files (<tt>source :upload</tt>);
      # the default is +:download+.
      def source(value)
        raise ArgumentError, "a runtime source is :download or :upload" unless %i[download upload].include?(value)

        @source = value
      end

      # Adds the version +version+ of a downloaded runtime, fetched from the
      # URL prefix +source+. +checksums+ is the path of its checksum file
      # (default: the builtin one). Raises ArgumentError when the file is
      # missing or empty.
      def version(version, source:, checksums: nil)
        path = checksums || File.join(CHECKSUMS, "#{@name}-#{version}.sha256")
        list = Builder.read_checksums(path)
        raise ArgumentError, "#{@name} #{version}: no checksums in #{path}" if list.empty?

        @versions[version.to_s] = Version.new(version: version.to_s, source: source.to_s, checksums: list.freeze)
      end

      # Sets the files every version of an uploaded runtime holds.
      def files(*names) = @files = names.flatten.map(&:to_s)

      # Adds the component kind +kind+ whose files match the +patterns+
      # (globs with <tt>%{key}</tt>).
      def component(kind, *patterns)
        @components[kind.to_s] = Component.new(kind: kind.to_s, patterns: patterns.flatten.map(&:to_s).freeze)
      end

      # Adds the parameter +name+; see Param.
      def param(name, type: :string, required: false, component: nil, default: nil)
        @params[name.to_sym] = Param.new(name: name.to_sym, type: type, required: required,
                                         component: component&.to_s, default: default.freeze)
      end

      # Sets the licence notice installed beside the files: a builtin notice
      # name or a path (default: the builtin <tt><name>.txt</tt> when there is one).
      def notice(value)
        value = value.to_s
        @notice = File.exist?(value) ? value : File.join(NOTICES, value)
      end

      # Sets the block that generates the controls help from the resolved
      # parameters (a Hash with String keys); it returns rows for
      # WarpEngine::Runtime::Controls.normalize.
      #
      #   controls { |params| [ { "keys" => [params["fire"]], "action" => "Fire" } ] }
      def controls(&block) = @controls = block

      # Sets the page template: a builtin template name or a path.
      def template(value)
        value = value.to_s
        @template = File.exist?(value) ? value : File.join(TEMPLATES, value)
      end

      # Returns the Definition. Raises ArgumentError when the template is
      # missing or a downloaded runtime has no version.
      def build
        raise ArgumentError, "runtime #{@name}: no template at #{@template}" unless File.file?(@template)
        raise ArgumentError, "runtime #{@name}: a downloaded runtime needs a version" if @source == :download && @versions.empty?
        raise ArgumentError, "runtime #{@name}: no notice at #{@notice}" if @notice && !File.file?(@notice)

        Definition.new(name: @name, label: @label, license: @license, source: @source, versions: @versions.freeze,
                       files: @files.freeze, components: @components.freeze, params: @params.freeze,
                       template: @template, notice: @notice, controls: @controls)
      end

      # Returns the checksum file +path+ (lines of <tt>digest  file</tt>) as a
      # Hash of file to digest; an empty Hash when the file is missing.
      def self.read_checksums(path)
        return {} unless File.file?(path.to_s)

        File.foreach(path.to_s).each_with_object({}) do |line, list|
          digest, file = line.strip.split(/\s+\*?/, 2)
          list[file] = digest.downcase if digest&.match?(/\A\h{64}\z/) && file.present?
        end
      end
    end
  end
end
