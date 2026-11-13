module WarpEngine
  module Platforms
    # The pre-1.12 way to write a platform: a service class that includes this
    # concern and one Builds module per asset kind, registered with
    # <tt>register_platform "name", service: "..."</tt>. Deprecated: a platform
    # is now a WarpEngine::Platform::Definition, declared with the
    # WarpEngine::Platform::Builder DSL. The concern keeps old services working:
    # their declarations become a Definition (Updatable::ClassMethods#definition)
    # and #update publishes through WarpEngine::Publish::Publisher.
    #
    #   class AmigaService
    #     include WarpEngine::Platforms::Updatable
    #     include WarpEngine::Platforms::Builds::BuildCartridge
    #
    #     label "Amiga"
    #     required_kinds "cartridge"
    #     def cartridge_ext = ".adf"
    #   end
    module Updatable
      extend ActiveSupport::Concern

      # Class-level declarations of a legacy platform service.
      class_methods do
        # The platform name. With +value+ sets it; without, defaults to the
        # downcased name of the enclosing module.
        def platform(value = nil)
          @platform = value if value
          @platform ||= name.deconstantize.demodulize.downcase
        end

        # The human readable platform name. With +value+ sets it; without, the
        # titleized #platform.
        def label(value = nil)
          @label = value if value
          @label ||= platform.titleize
        end

        # The asset kinds the platform publishes, in the order the Builds modules
        # registered them.
        def expected_kinds = (@expected_kinds ||= [])

        # Adds +kind+ to #expected_kinds unless it is there already.
        def register_expected_kind(kind)
          expected_kinds << kind unless expected_kinds.include?(kind)
        end

        # The kinds an upload must contain. With +kinds+ adds them.
        def required_kinds(*kinds)
          @required_kinds ||= []
          @required_kinds |= kinds.flatten.map(&:to_s)
        end

        # The kinds a release may lack without counting as missing. With +kinds+
        # adds them.
        def optional_kinds(*kinds)
          @optional_kinds ||= []
          @optional_kinds |= kinds.flatten.map(&:to_s)
        end

        # The CI release rule (<tt>"tag"</tt>), or +nil+. With +value+ sets it.
        def release_rule(value = nil)
          @release_rule = value.to_s if value
          @release_rule
        end

        # The folder spec of a +folders+ shelf; +nil+ unless overridden.
        def shelf_folder(_metadata, _kind) = nil

        # The instance method names #update calls with <tt>name-version</tt>
        # before it publishes.
        def prepare_steps = (@prepare_steps ||= [])

        # Adds +method_name+ to #prepare_steps unless it is there already.
        def register_prepare_step(method_name)
          prepare_steps << method_name unless prepare_steps.include?(method_name)
        end

        # Returns the WarpEngine::Platform::Definition of the declarations: the
        # extension of a kind without a suffix comes from the
        # <tt><kind>_ext</tt> instance method.
        def definition
          instance = new
          specs = expected_kinds.map do |kind|
            ext = instance.public_send(:"#{kind}_ext") if instance.respond_to?(:"#{kind}_ext")
            required = required_kinds.include?(kind)
            WarpEngine::Platform::KindSpec.new(kind: WarpEngine::AssetKinds.fetch(kind), ext: ext, required: required,
                                               optional: optional_kinds.include?(kind), built: true, always: required)
          end
          WarpEngine::Platform::Definition.new(
            name: platform, label: label, kind_specs: specs, metadata: :json, release_rule: release_rule,
            shelf_folder: method(:shelf_folder), ci_template: nil, ci_variables: {}, version_source: nil
          )
        end
      end

      # Runs the #prepare_steps, then publishes the upload <tt>name-version</tt>
      # through WarpEngine::Publish::Publisher, reading the metadata with
      # #parse_metadata. Returns the WarpEngine::Release; raises
      # MissingAssetsError when a required kind is missing.
      def update(name, version)
        versioned = "#{name}-#{version}"
        self.class.prepare_steps.each { |step| send(step, versioned) }
        WarpEngine::Publish::Publisher.new(self.class.definition, metadata: ->(upload) { parse_metadata(upload.versioned) })
                                      .publish(name, version)
      end

      private

      def parse_metadata(versioned) = parse_json_metadata(full_path("#{versioned}.metadata.json"))

      def parse_json_metadata(path) = WarpEngine::Publish::MetadataReader.json(path)

      def parse_lua_metadata(path) = WarpEngine::Publish::MetadataReader.lua(path)

      def full_path(filename) = File.join(WarpEngine.config.file_container_path, filename)

      def dir_exists?(dirname) = File.directory?(full_path(dirname))

      def extract_zip_to_dir(zip_file, dir_name)
        WarpEngine::Publish::Unpacker.new.replace_dir(full_path(zip_file), full_path(dir_name))
      end
    end
  end
end
