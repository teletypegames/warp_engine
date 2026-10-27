require "uri"

module WarpEngine
  module Shelves
    INDEX_FILE = "INDEX.TXT".freeze
    NAME_PATTERN = /\A[A-Z0-9-]+\z/
    EXTENSION_PATTERN = /\A\.[A-Z0-9]{1,8}\z/
    LAYOUTS = %w[flat folders].freeze
    URL_SCHEMES = %w[ftp http https].freeze
    KEYS = %i[platform kind kinds layout path extension name_length statuses urls].freeze

    class ConfigurationError < StandardError; end

    Shelf = Struct.new(:platform, :kinds, :layout, :path, :extension, :name_length, :statuses, :urls, keyword_init: true) do
      def directory
        File.join(WarpEngine.config.file_container_path, path)
      end

      def folders? = layout == "folders"

      def base_length = folders? ? name_length : name_length - extension.length

      def file_name_for(software)
        base = Shelves.normalize_name(software.shelf_name.presence || software.name)
        base = base[0, base_length].sub(/-+\z/, "")
        base.empty? ? nil : "#{base}#{extension}"
      end

      def folder_name_valid?(name)
        name.is_a?(String) && name.match?(NAME_PATTERN) && name.length <= name_length
      end

      def listed_statuses
        statuses.presence || WarpEngine::SoftwareStatus.default_visible_keys
      end

      def describe = "#{platform} (#{kinds.join(', ')}, #{layout})"
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

      def descriptors
        all.map do |shelf|
          { platform: shelf.platform, kinds: shelf.kinds, layout: shelf.layout, index: INDEX_FILE, urls: shelf.urls }
        end
      rescue ConfigurationError
        []
      end

      private

      def build(definition)
        attributes = definition.to_h.symbolize_keys
        unknown = attributes.keys - KEYS
        raise ConfigurationError, "unknown shelf keys: #{unknown.join(', ')}" if unknown.any?

        layout = (attributes[:layout] || "flat").to_s
        shelf = Shelf.new(
          platform:    attributes[:platform].to_s,
          kinds:       Array(attributes[:kinds] || attributes[:kind]).map(&:to_s),
          layout:      layout,
          path:        attributes[:path].to_s,
          extension:   attributes[:extension].to_s.upcase,
          name_length: Integer(attributes.fetch(:name_length, layout == "folders" ? 8 : 16)),
          statuses:    Array(attributes[:statuses]).map(&:to_s),
          urls:        Array(attributes[:urls]).map(&:to_s)
        )
        check!(shelf)
        shelf
      end

      def check!(shelf)
        raise ConfigurationError, "unknown shelf platform: #{shelf.platform.inspect}" unless WarpEngine::Platform.exists?(shelf.platform)
        raise ConfigurationError, "a shelf needs a kind" if shelf.kinds.empty?

        unknown_kinds = shelf.kinds - WarpEngine::ReleaseAsset::KINDS
        raise ConfigurationError, "unknown shelf kind: #{unknown_kinds.first.inspect}" if unknown_kinds.any?
        raise ConfigurationError, "unknown shelf layout: #{shelf.layout.inspect}" unless LAYOUTS.include?(shelf.layout)

        if shelf.folders?
          raise ConfigurationError, "a folders shelf takes no extension" if shelf.extension.present?
        else
          raise ConfigurationError, "shelf extension must look like .PRG: #{shelf.extension.inspect}" unless shelf.extension.match?(EXTENSION_PATTERN)
        end
        raise ConfigurationError, "shelf name_length leaves no room for a name" unless shelf.base_length.positive?

        path = Pathname.new(shelf.path)
        if shelf.path.empty? || path.absolute? || path.each_filename.include?("..")
          raise ConfigurationError, "shelf path must be relative to file_container_path: #{shelf.path.inspect}"
        end

        shelf.urls.each do |url|
          scheme = URI.parse(url).scheme
          raise ConfigurationError, "shelf url needs one of #{URL_SCHEMES.join(', ')}: #{url.inspect}" unless URL_SCHEMES.include?(scheme)
        rescue URI::InvalidURIError
          raise ConfigurationError, "shelf url is not a URL: #{url.inspect}"
        end
      end
    end
  end
end
