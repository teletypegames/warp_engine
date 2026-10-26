module WarpEngine
  module Platforms
    module Updatable
      extend ActiveSupport::Concern
      include ArchiveExtraction
      include MetadataParsing
      include SoftwarePersistence

      class_methods do
        def platform(value = nil)
          @platform = value if value
          @platform ||= name.deconstantize.demodulize.downcase
        end

        def label(value = nil)
          @label = value if value
          @label ||= platform.titleize
        end

        def expected_kinds
          @expected_kinds ||= []
        end

        def register_expected_kind(kind)
          expected_kinds << kind unless expected_kinds.include?(kind)
        end

        def required_kinds(*kinds)
          @required_kinds ||= []
          @required_kinds |= kinds.flatten.map(&:to_s)
        end

        def optional_kinds(*kinds)
          @optional_kinds ||= []
          @optional_kinds |= kinds.flatten.map(&:to_s)
        end

        def prepare_steps
          @prepare_steps ||= []
        end

        def register_prepare_step(method_name)
          prepare_steps << method_name unless prepare_steps.include?(method_name)
        end
      end

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

      def prepare_files(versioned)
        self.class.prepare_steps.each { |step| send(step, versioned) }
      end

      def parse_metadata(versioned)
        parse_json_metadata(full_path("#{versioned}.metadata.json"))
      end

      def collect_asset_paths(versioned)
        self.class.expected_kinds.each_with_object({}) do |kind, hash|
          result = send(:"#{kind}_asset_path", versioned)
          hash.merge!(result) if result
        end
      end
    end
  end
end
