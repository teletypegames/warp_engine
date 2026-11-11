require "uri"

module WarpEngine
  # Shelves: folders the engine keeps in step with the catalog, holding the
  # latest build of every public title of one platform under a fixed,
  # versionless name, plus an INDEX_FILE listing them. They serve clients that
  # cannot read the JSON API (a C64 store over HTTP, a DOS installer over FTP).
  #
  #   shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG", name_length: 16, preview: "c64"
  #
  # The definitions live in WarpEngine.config.shelves; WarpEngine::ShelfService
  # writes the folders.
  module Shelves
    # The name of the index file written into every shelf.
    INDEX_FILE = "INDEX.TXT".freeze
    # The characters a shelf file or folder name may consist of.
    NAME_PATTERN = /\A[A-Z0-9-]+\z/
    # The form a flat shelf's extension must have, e.g. +.PRG+.
    EXTENSION_PATTERN = /\A\.[A-Z0-9]{1,8}\z/
    # The shelf layouts: +flat+ (one file a title) and +folders+ (one folder a title).
    LAYOUTS = %w[flat folders].freeze
    # The URL schemes a shelf's +urls+ may use.
    URL_SCHEMES = %w[ftp http https].freeze
    # The keys a shelf definition accepts.
    KEYS = %i[platform kind kinds layout path extension name_length statuses urls preview].freeze

    # Raised when a shelf definition is invalid.
    class ConfigurationError < StandardError; end

    # One validated shelf definition.
    #
    # [platform]    the platform name
    # [kinds]       the release asset kinds it takes
    # [layout]      +flat+ or +folders+
    # [path]        the folder, relative to +file_container_path+
    # [extension]   the extension of a flat shelf's files, in capitals
    # [name_length] the longest file name (extension included) or folder name
    # [statuses]    the software statuses listed; empty means the default visible ones
    # [urls]        where the host serves the folder
    # [preview]     the WarpEngine::ShelfPreview format written beside each
    #               title of a flat shelf, or +nil+ for none
    Shelf = Struct.new(:platform, :kinds, :layout, :path, :extension, :name_length, :statuses, :urls, :preview,
                       keyword_init: true) do
      # Returns the absolute path of the shelf folder.
      def directory
        File.join(WarpEngine.config.file_container_path, path)
      end

      # Returns +true+ for a +folders+ layout.
      def folders? = layout == "folders"

      # Returns the longest name without the extension.
      def base_length = folders? ? name_length : name_length - extension.length

      # Returns the shelf file name of +software+: its +shelf_name+ or +name+,
      # normalized, cut to #base_length, plus the extension; +nil+ when nothing
      # of the name is left.
      def file_name_for(software)
        base = Shelves.normalize_name(software.shelf_name.presence || software.name)
        base = base[0, base_length].sub(/-+\z/, "")
        base.empty? ? nil : "#{base}#{extension}"
      end

      # Returns the WarpEngine::ShelfPreview renderer class of the shelf, or +nil+.
      def preview_renderer = preview && WarpEngine::ShelfPreview.for(preview)

      # Returns the name of the preview beside the shelf file +file+: the file
      # name with the extension of the renderer (<tt>ARIADNE.PVW</tt>).
      def preview_name_for(file) = "#{file.delete_suffix(extension)}#{preview_renderer::EXTENSION}"

      # Returns +true+ when +name+ is a String of NAME_PATTERN characters no
      # longer than +name_length+.
      def folder_name_valid?(name)
        name.is_a?(String) && name.match?(NAME_PATTERN) && name.length <= name_length
      end

      # Returns the status keys the shelf lists: +statuses+, or the default
      # visible keys of WarpEngine::SoftwareStatus.
      def listed_statuses
        statuses.presence || WarpEngine::SoftwareStatus.default_visible_keys
      end

      # Returns a one-line description, e.g. <tt>c64 (cartridge, flat)</tt>.
      def describe = "#{platform} (#{kinds.join(', ')}, #{layout})"
    end

    class << self
      # Returns every configured shelf as a Shelf. Raises ConfigurationError on an
      # invalid definition.
      def all
        Array(WarpEngine.config.shelves).map { |definition| build(definition) }
      end

      # Returns +true+ when any shelf is configured.
      def any? = Array(WarpEngine.config.shelves).any?

      # Returns the shelves of +platform+.
      def for_platform(platform)
        all.select { |shelf| shelf.platform == platform.to_s }
      end

      # Builds and checks every shelf, and returns them. Raises ConfigurationError
      # on an invalid definition, when shelves are configured with a storage
      # adapter other than the local one, or when two shelves share a path.
      def validate!
        shelves = all
        raise ConfigurationError, "shelves need the :local storage adapter" if shelves.any? && !WarpEngine::Storage.local?

        duplicates = shelves.group_by(&:path).select { |_, group| group.size > 1 }.keys
        raise ConfigurationError, "two shelves share the path #{duplicates.first}" if duplicates.any?

        shelves
      end

      # Returns +value+ as a shelf name: transliterated to ASCII, upcased, every
      # run of other characters than <tt>A-Z 0-9 -</tt> turned into one dash,
      # leading and trailing dashes removed.
      def normalize_name(value)
        I18n.transliterate(value.to_s).upcase.gsub(/[^A-Z0-9-]+/, "-").squeeze("-").gsub(/\A-+|-+\z/, "")
      end

      # Syncs the shelves of +platform+ (every shelf when +nil+) with the catalog
      # through WarpEngine::ShelfService#sync!, rewriting their folders. Returns
      # the sync results; returns an empty Array when no shelf is configured, or
      # logs the error and returns an empty Array when the sync fails.
      def refresh(platform: nil)
        return [] unless any?

        shelves = platform.nil? ? all : for_platform(platform)
        shelves.map { |shelf| WarpEngine::ShelfService.new(shelf).sync! }
      rescue StandardError => e
        Rails.logger.error("[WarpEngine::Shelves] refresh #{platform || 'all'}: #{e.class}: #{e.message}")
        []
      end

      # Returns a Hash for each shelf (+platform+, +kinds+, +layout+, +index+,
      # +urls+), as <tt>GET /api/service</tt> lists them; an empty Array when the
      # configuration is invalid.
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
          urls:        Array(attributes[:urls]).map(&:to_s),
          preview:     attributes[:preview]&.to_s.presence
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

        if shelf.preview
          raise ConfigurationError, "unknown shelf preview: #{shelf.preview.inspect}" unless shelf.preview_renderer
          raise ConfigurationError, "a folders shelf takes no preview" if shelf.folders?
        end

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
