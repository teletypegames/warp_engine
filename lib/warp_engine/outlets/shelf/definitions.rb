require "uri"

module WarpEngine
  module Outlets
    class Shelf < Base
      # Shelves: folders the engine keeps in step with the catalog, holding the
      # latest build of every public title of one platform under a fixed,
      # versionless name, plus an INDEX_FILE listing them. They serve clients that
      # cannot read the JSON API (a C64 store over HTTP, a DOS installer over FTP).
      #
      #   shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG", name_length: 16, preview: "c64"
      #
      # The definitions live in WarpEngine.config.shelves; WarpEngine::ShelfService
      # writes the folders. Before 1.12 this module was WarpEngine::Shelves, which
      # is still its alias.
      module Definitions
        # The name of the index file written into every shelf (Shelf::IndexFile::NAME).
        INDEX_FILE = IndexFile::NAME
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
        # The error an invalid definition raises: WarpEngine::ConfigurationError.
        ConfigurationError = WarpEngine::ConfigurationError

        # The former name of Shelf::Definition, kept for hosts that refer to it.
        Shelf = Definition

        class << self
          # Returns every configured shelf as a Shelf::Definition. Raises ConfigurationError on an
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
            shelf = Definition.new(
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
  end
end
