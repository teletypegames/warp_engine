module WarpEngine
  module Shelves
    INDEX_FILE = "INDEX.TXT".freeze
    NAME_PATTERN = /\A[A-Z0-9-]+\z/
    EXTENSION_PATTERN = /\A\.[A-Z0-9]{1,8}\z/

    class ConfigurationError < StandardError; end

    Shelf = Struct.new(:platform, :kind, :path, :extension, :name_length, :statuses, keyword_init: true) do
      def directory
        File.join(WarpEngine.config.file_container_path, path)
      end

      def base_length = name_length - extension.length

      def file_name_for(software)
        base = Shelves.normalize_name(software.shelf_name.presence || software.name)
        base = base[0, base_length].sub(/-+\z/, "")
        base.empty? ? nil : "#{base}#{extension}"
      end

      def listed_statuses
        statuses.presence || WarpEngine::SoftwareStatus.default_visible_keys
      end
    end

    class << self
      def all
        Array(WarpEngine.config.shelves).map { |definition| build(definition) }
      end

      def any? = Array(WarpEngine.config.shelves).any?

      def for_platform(platform)
        all.select { |shelf| shelf.platform == platform.to_s }
      end

      def validate!
        shelves = all
        raise ConfigurationError, "shelves need the :local storage adapter" if shelves.any? && !WarpEngine::Storage.local?

        duplicates = shelves.group_by(&:path).select { |_, group| group.size > 1 }.keys
        raise ConfigurationError, "two shelves share the path #{duplicates.first}" if duplicates.any?

        shelves
      end

      def normalize_name(value)
        I18n.transliterate(value.to_s).upcase.gsub(/[^A-Z0-9-]+/, "-").squeeze("-").gsub(/\A-+|-+\z/, "")
      end

      def refresh(platform: nil)
        return [] unless any?

        shelves = platform.nil? ? all : for_platform(platform)
        shelves.map { |shelf| WarpEngine::ShelfService.new(shelf).sync! }
      rescue StandardError => e
        Rails.logger.error("[WarpEngine::Shelves] refresh #{platform || 'all'}: #{e.class}: #{e.message}")
        []
      end

      private

      def build(definition)
        attributes = definition.to_h.symbolize_keys
        unknown = attributes.keys - Shelf.members
        raise ConfigurationError, "unknown shelf keys: #{unknown.join(', ')}" if unknown.any?

        shelf = Shelf.new(
          platform:    attributes[:platform].to_s,
          kind:        attributes[:kind].to_s,
          path:        attributes[:path].to_s,
          extension:   attributes[:extension].to_s.upcase,
          name_length: Integer(attributes.fetch(:name_length, 16)),
          statuses:    Array(attributes[:statuses]).map(&:to_s)
        )
        check!(shelf)
        shelf
      end

      def check!(shelf)
        raise ConfigurationError, "unknown shelf platform: #{shelf.platform.inspect}" unless WarpEngine::Platform.exists?(shelf.platform)
        raise ConfigurationError, "unknown shelf kind: #{shelf.kind.inspect}" unless WarpEngine::ReleaseAsset::KINDS.include?(shelf.kind)
        raise ConfigurationError, "shelf extension must look like .PRG: #{shelf.extension.inspect}" unless shelf.extension.match?(EXTENSION_PATTERN)
        raise ConfigurationError, "shelf name_length leaves no room for a name" unless shelf.base_length.positive?

        path = Pathname.new(shelf.path)
        if shelf.path.empty? || path.absolute? || path.each_filename.include?("..")
          raise ConfigurationError, "shelf path must be relative to file_container_path: #{shelf.path.inspect}"
        end
      end
    end
  end
end
