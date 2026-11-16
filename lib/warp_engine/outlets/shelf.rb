require "uri"
require "warp_engine/files"
require "warp_engine/outlets/base"
require "warp_engine/names"

module WarpEngine
  module Outlets
    # A shelf: a folder of the file container the engine keeps in step with
    # the catalog, holding the latest build of every listed title of one
    # platform under a fixed, versionless name, plus an <tt>INDEX.TXT</tt>
    # (Shelf::IndexFile). It serves clients that cannot read the JSON API (a
    # C64 store over HTTP, a DOS installer over FTP). Shelf::Builder writes it,
    # in the Shelf::Layouts of the shelf, with the Shelf::Preview pictures.
    #
    #   shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG", preview: "c64"
    #   outlet :apps, type: :shelf, platform: :dos, kinds: %w[cartridge win_x86], layout: "folders", path: "shelves/APPS"
    #
    # Options:
    #
    # [platform]    the platform name (required)
    # [kind, kinds] the release asset kinds it takes
    # [layout]      +flat+ (one file a title, the default) or +folders+ (one folder a title)
    # [path]        the folder, relative to +file_container_path+
    # [extension]   the extension of a flat shelf's files (<tt>.PRG</tt>), stored in capitals
    # [name_length] the longest file name (extension included) or folder name;
    #               default 16 flat, 8 folders
    # [statuses]    the software statuses listed; empty for the default visible ones
    # [urls]        where the host serves the folder (+ftp+, +http+, +https+)
    # [preview]     the Shelf::Preview format written beside each title of a
    #               flat shelf, or none
    #
    # Shelves need the +:local+ storage adapter, and no two may share a folder.
    class Shelf < Base
      include Materialized

      # The options a shelf takes.
      OPTIONS = %i[platform kind kinds layout path extension name_length statuses urls preview].freeze
      # The shelf layouts: +flat+ (one file a title) and +folders+ (one folder a title).
      LAYOUTS = %w[flat folders].freeze
      # The form a flat shelf's extension must have, e.g. +.PRG+.
      EXTENSION_PATTERN = /\A\.[A-Z0-9]{1,8}\z/
      # The URL schemes a shelf's +urls+ may use.
      URL_SCHEMES = %w[ftp http https].freeze

      class << self
        # Returns +shelf+.
        def type_name = "shelf"

        # Checks that the +shelves+ can be kept: the storage is the local
        # filesystem and no two share a path. Raises ConfigurationError
        # otherwise; returns +shelves+.
        def validate_all!(shelves)
          return shelves if shelves.empty?
          raise ConfigurationError, "shelves need the :local storage adapter" unless WarpEngine::Storage.local?

          duplicate = shelves.map(&:path).tally.find { |_, count| count > 1 }&.first
          raise ConfigurationError, "two shelves share the path #{duplicate}" if duplicate

          shelves
        end
      end

      # Returns the platform name.
      def platform = options[:platform].to_s

      # Returns the shelf's platform, as the only one it carries.
      def platforms = [ platform ]

      # Returns the release asset kinds it takes.
      def kinds = Array(options[:kinds] || options[:kind]).map(&:to_s)

      # Returns +flat+ or +folders+.
      def layout = (options[:layout] || "flat").to_s

      # Returns +true+ for a +folders+ layout.
      def folders? = layout == "folders"

      # Returns the folder, relative to +file_container_path+.
      def path = options[:path].to_s

      # Returns the absolute path of the shelf folder.
      def directory = File.join(WarpEngine.config.file_container_path, path)

      # Returns the extension of a flat shelf's files, in capitals; empty on a
      # +folders+ shelf.
      def extension = options[:extension].to_s.upcase

      # Returns the longest file name (extension included) or folder name.
      def name_length = Integer(options.fetch(:name_length, folders? ? 8 : 16))

      # Returns the longest name without the extension.
      def base_length = name_length - extension.length

      # Returns the status keys listed; empty for the default visible ones.
      def statuses = option_list(:statuses)

      # Returns where the host serves the folder.
      def urls = option_list(:urls)

      # Returns the Shelf::Preview format, or +nil+ for none.
      def preview = options[:preview]&.to_s.presence

      # Returns the Shelf::Preview renderer class of the shelf, or +nil+.
      def preview_renderer = preview && Preview.for(preview)

      # Returns the name of the preview beside the shelf file +file+: the file
      # name with the extension of the renderer (<tt>ARIADNE.PVW</tt>).
      def preview_name_for(file) = "#{file.delete_suffix(extension)}#{preview_renderer::EXTENSION}"

      # Returns the shelf file name of +software+ (WarpEngine::Names.file_name
      # cut to #name_length with the #extension), or +nil+ when nothing of the
      # name is left.
      def file_name_for(software) = Names.file_name(software, length: name_length, extension: extension)

      # Returns +true+ when +name+ is a String of the allowed characters
      # (WarpEngine::Names::PATTERN) no longer than #name_length.
      def folder_name_valid?(name)
        name.is_a?(String) && name.match?(WarpEngine::Names::PATTERN) && name.length <= name_length
      end

      # Returns the WarpEngine::Catalog::Offer of the shelf: its platform, kinds
      # and listed statuses.
      def offer
        @offer ||= WarpEngine::Catalog::Offer.new(platforms: platforms, kinds: kinds, statuses: statuses)
      end

      # Checks the options: known keys, platform, kinds, layout, extension,
      # name length, preview, path and urls. Raises ConfigurationError when one
      # is invalid; returns +self+.
      def validate!
        check_keys!(OPTIONS)
        check_platforms!([ platform ])
        check_kinds!(kinds)
        raise ConfigurationError, "#{key}: unknown layout #{layout.inspect}" unless LAYOUTS.include?(layout)

        check_extension!
        raise ConfigurationError, "#{key}: name_length leaves no room for a name" unless base_length.positive?

        check_preview!
        check_path!
        check_urls!
        self
      rescue ArgumentError, TypeError => e
        raise ConfigurationError, "#{key}: #{e.message}"
      end

      # Returns the Base#descriptor with the shelf's +kinds+, +layout+, +index+
      # file and +urls+.
      def descriptor
        super.merge(kinds: kinds, layout: layout, index: IndexFile::NAME, urls: urls)
      end

      # Returns a one-line description, e.g.
      # <tt>c64 (shelf: c64; cartridge; flat; shelves/C64)</tt>.
      def describe = "#{key} (#{type}: #{platform}; #{kinds.join(', ')}; #{layout}; #{path})"

      # Decides what the shelf holds without touching the disk (Shelf::Builder#plan).
      # Returns <tt>[entries, skipped]</tt>.
      def plan = builder.plan

      # Rebuilds the shelf through Shelf::Builder#sync!. Returns its
      # Shelf::Builder::Result.
      def sync!(dry_run: false) = builder.sync!(dry_run: dry_run)

      # Returns the lines of the check: where the shelf is served, every file
      # on it and every software it leaves out.
      def report
        entries, skipped = plan
        urls.map { |url| "  served  #{url}" } +
          entries.map { |entry| "  ok      #{entry.file.ljust(name_length)} #{entry.version}  #{entry.software.name} (#{entry.kind})" } +
          skipped.map { |skip| "  skipped #{skip}" }
      end

      private

      def builder = Builder.new(self)

      def check_extension!
        if folders?
          raise ConfigurationError, "#{key}: a folders shelf takes no extension" if extension.present?
        elsif !extension.match?(EXTENSION_PATTERN)
          raise ConfigurationError, "#{key}: extension must look like .PRG: #{extension.inspect}"
        end
      end

      def check_preview!
        return unless preview
        raise ConfigurationError, "#{key}: unknown preview #{preview.inspect}" unless preview_renderer
        raise ConfigurationError, "#{key}: a folders shelf takes no preview" if folders?
      end

      def check_path!
        folder = Pathname.new(path)
        return unless path.empty? || folder.absolute? || folder.each_filename.include?("..")

        raise ConfigurationError, "#{key}: path must be relative to file_container_path: #{path.inspect}"
      end

      def check_urls!
        urls.each do |url|
          scheme = URI.parse(url).scheme
          raise ConfigurationError, "#{key}: url needs one of #{URL_SCHEMES.join(', ')}: #{url.inspect}" unless URL_SCHEMES.include?(scheme)
        rescue URI::InvalidURIError
          raise ConfigurationError, "#{key}: url is not a URL: #{url.inspect}"
        end
      end
    end
  end
end

require "warp_engine/outlets/shelf/index_file"
require "warp_engine/outlets/shelf/layouts"
require "warp_engine/outlets/shelf/preview"
require "warp_engine/outlets/shelf/builder"
