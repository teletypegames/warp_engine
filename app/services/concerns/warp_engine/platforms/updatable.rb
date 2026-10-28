module WarpEngine
  # Platform support: one service class per platform
  # (<tt>WarpEngine::Platforms::<Name>::Service</tt>) that turns a CI upload into
  # catalog records, plus the concerns they are built from.
  module Platforms
    # The base concern of every platform service. Including it gives the class
    # the declarations below (+label+, +required_kinds+, ...) and the #update
    # entry point; the Builds concerns register the asset kinds the platform
    # produces and the steps that prepare them.
    #
    #   class Service
    #     include Updatable
    #     include Builds::BuildWeb
    #     include Builds::BuildWinX64
    #
    #     label "Phaser"
    #     required_kinds "html"
    #   end
    module Updatable
      extend ActiveSupport::Concern
      include ArchiveExtraction
      include MetadataParsing
      include SoftwarePersistence

      # Class-level declarations of a platform service.
      class_methods do
        # The platform name. With +value+ sets it; without, defaults to the
        # downcased name of the enclosing module (+c64+ for
        # <tt>WarpEngine::Platforms::C64::Service</tt>).
        def platform(value = nil)
          @platform = value if value
          @platform ||= name.deconstantize.demodulize.downcase
        end

        # The human readable platform name. With +value+ sets it; without, defaults
        # to the titleized #platform.
        def label(value = nil)
          @label = value if value
          @label ||= platform.titleize
        end

        # The asset kinds (WarpEngine::ReleaseAsset kinds) the platform produces, in
        # the order the Builds concerns registered them.
        def expected_kinds
          @expected_kinds ||= []
        end

        # Adds +kind+ to #expected_kinds unless it is there already. Called by the
        # Builds concerns when included.
        def register_expected_kind(kind)
          expected_kinds << kind unless expected_kinds.include?(kind)
        end

        # The asset kinds an upload must contain. With +kinds+ adds them (as strings)
        # to the list. Updatable#update raises MissingAssetsError when one is missing.
        def required_kinds(*kinds)
          @required_kinds ||= []
          @required_kinds |= kinds.flatten.map(&:to_s)
        end

        # The asset kinds that may be missing from a release without counting as
        # missing in the build checks. With +kinds+ adds them (as strings) to the list.
        def optional_kinds(*kinds)
          @optional_kinds ||= []
          @optional_kinds |= kinds.flatten.map(&:to_s)
        end

        # The CI release rule of the platform (for example <tt>"tag"</tt>), or +nil+ for
        # the default. With +value+ sets it.
        def release_rule(value = nil)
          @release_rule = value.to_s if value
          @release_rule
        end

        # The folder spec of a +folders+ shelf for asset +kind+, read from the
        # release's uploaded +metadata+. Returns +nil+ here: a platform that serves a
        # folders shelf overrides it (see WarpEngine::Platforms::Dos::Service.shelf_folder).
        def shelf_folder(_metadata, _kind) = nil

        # The instance method names #update calls with the <tt>name-version</tt> before
        # it collects the assets (for example unpacking an uploaded zip).
        def prepare_steps
          @prepare_steps ||= []
        end

        # Adds +method_name+ to #prepare_steps unless it is there already.
        def register_prepare_step(method_name)
          prepare_steps << method_name unless prepare_steps.include?(method_name)
        end
      end

      # Publishes the upload <tt>name-version</tt> found in the file container: runs
      # the prepare steps (unpacking zips), collects the asset of every expected
      # kind, reads the metadata, then in one transaction creates or updates the
      # WarpEngine::Software (with its "Source Code" and "Repository" external links
      # from +site+ and +repo+), creates the WarpEngine::Release if new, writes its
      # WarpEngine::ReleaseAsset records and soft-deletes assets of kinds the
      # platform no longer expects.
      #
      # [name]    the software name
      # [version] the version string
      #
      # Returns the WarpEngine::Release. Raises MissingAssetsError when a required
      # kind is missing, and ActiveRecord::RecordInvalid when a record does not save.
      def update(name, version)
        versioned = "#{name}-#{version}"
        prepare_files(versioned)

        asset_paths = collect_asset_paths(versioned)
        missing = self.class.required_kinds - asset_paths.keys
        raise MissingAssetsError.new(versioned, missing) if missing.any?

        metadata = parse_metadata(versioned)
        site_url = metadata.delete(:site)
        repo_url = metadata.delete(:repo)

        ActiveRecord::Base.transaction do
          software = update_or_create_software(metadata.merge(platform: self.class.platform))
          upsert_external_link(software.id, "Source Code", site_url) if site_url.present?
          upsert_external_link(software.id, "Repository", repo_url) if repo_url.present?

          release = create_release_if_not_exists(software_id: software.id, version: version)
          sync_release_assets(release, asset_paths)
          discard_unexpected_assets(release, self.class.expected_kinds)
          release
        end
      end

      private

      # Runs every registered prepare step on +versioned+.
      def prepare_files(versioned)
        self.class.prepare_steps.each { |step| send(step, versioned) }
      end

      # Reads the metadata of +versioned+ from <tt><name-version>.metadata.json</tt>.
      # Platforms override it to read another source.
      def parse_metadata(versioned)
        parse_json_metadata(full_path("#{versioned}.metadata.json"))
      end

      # Returns the <tt>kind => path</tt> Hash of the expected kinds present for
      # +versioned+, asking each <tt><kind>_asset_path</tt> method.
      def collect_asset_paths(versioned)
        self.class.expected_kinds.each_with_object({}) do |kind, hash|
          result = send(:"#{kind}_asset_path", versioned)
          hash.merge!(result) if result
        end
      end
    end
  end
end
