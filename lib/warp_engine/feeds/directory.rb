require "uri"
require "warp_engine/files"
require "warp_engine/feeds/base"
require "warp_engine/names"

module WarpEngine
  module Feeds
    # A directory: a folder of the file container the engine keeps in step with
    # the catalog, holding the latest build of every listed title of one
    # platform under a fixed, versionless name, plus an <tt>INDEX.TXT</tt>
    # (Directory::IndexFile). It serves clients that cannot read the JSON API (a
    # C64 store over HTTP, a DOS installer over FTP). Directory::Builder writes it,
    # in the Directory::Layouts of the directory, with the Directory::Preview pictures.
    #
    #   directory :c64, kind: "package", path: "directories/C64", extension: ".PRG", preview: "c64"
    #   feed :apps, type: :directory, platform: :dos, kinds: %w[package win_x86], layout: "folders", path: "directories/APPS"
    #
    # Options:
    #
    # [platform]    the platform name (required)
    # [kind, kinds] the release asset kinds it takes
    # [layout]      +flat+ (one file a title, the default) or +folders+ (one folder a title)
    # [path]        the folder, relative to +file_container_path+
    # [extension]   the extension of a flat directory's files (<tt>.PRG</tt>), stored in capitals
    # [name_length] the longest file name (extension included) or folder name;
    #               default 16 flat, 8 folders
    # [statuses]    the software statuses listed; empty for the default visible ones
    # [urls]        where the host serves the folder (+ftp+, +http+, +https+)
    # [preview]     the Directory::Preview format written beside each title of a
    #               flat directory, or none
    #
    # Directories need the +:local+ storage adapter, and no two may share a folder.
    class Directory < Base
      include Static

      # The options a directory takes.
      OPTIONS = %i[platform kind kinds layout path extension name_length statuses urls preview].freeze
      # The directory layouts: +flat+ (one file a title) and +folders+ (one folder a title).
      LAYOUTS = %w[flat folders].freeze
      # The form a flat directory's extension must have, e.g. +.PRG+.
      EXTENSION_PATTERN = /\A\.[A-Z0-9]{1,8}\z/
      # The URL schemes a directory's +urls+ may use.
      URL_SCHEMES = %w[ftp http https].freeze

      class << self
        # Returns +directory+.
        def type_name = "directory"

        # Checks that the +directories+ can be kept: the storage is the local
        # filesystem and no two share a path. Raises ConfigurationError
        # otherwise; returns +directories+.
        def validate_all!(directories)
          return directories if directories.empty?
          raise ConfigurationError, "directories need the :local storage adapter" unless WarpEngine::Storage.local?

          duplicate = directories.map(&:path).tally.find { |_, count| count > 1 }&.first
          raise ConfigurationError, "two directories share the path #{duplicate}" if duplicate

          directories
        end
      end

      # Returns the platform name.
      def platform = options[:platform].to_s

      # Returns the directory's platform, as the only one it carries.
      def platforms = [ platform ]

      # Returns the release asset kinds it takes.
      def kinds = WarpEngine::AssetKinds.canonical_list(options[:kinds] || options[:kind])

      # Returns +flat+ or +folders+.
      def layout = (options[:layout] || "flat").to_s

      # Returns +true+ for a +folders+ layout.
      def folders? = layout == "folders"

      # Returns the folder, relative to +file_container_path+.
      def path = options[:path].to_s

      # Returns the absolute path of the directory folder.
      def directory = File.join(WarpEngine.config.file_container_path, path)

      # Returns the extension of a flat directory's files, in capitals; empty on a
      # +folders+ directory.
      def extension = options[:extension].to_s.upcase

      # Returns the longest file name (extension included) or folder name.
      def name_length = Integer(options.fetch(:name_length, folders? ? 8 : 16))

      # Returns the longest name without the extension.
      def base_length = name_length - extension.length

      # Returns the status keys listed; empty for the default visible ones.
      def statuses = option_list(:statuses)

      # Returns where the host serves the folder.
      def urls = option_list(:urls)

      # Returns the Directory::Preview format, or +nil+ for none.
      def preview = options[:preview]&.to_s.presence

      # Returns the Directory::Preview renderer class of the directory, or +nil+.
      def preview_renderer = preview && Preview.for(preview)

      # Returns the name of the preview beside the directory file +file+: the file
      # name with the extension of the renderer (<tt>ARIADNE.PVW</tt>).
      def preview_name_for(file) = "#{file.delete_suffix(extension)}#{preview_renderer::EXTENSION}"

      # Returns the directory file name of +software+ (WarpEngine::Names.file_name
      # cut to #name_length with the #extension), or +nil+ when nothing of the
      # name is left.
      def file_name_for(software) = Names.file_name(software, length: name_length, extension: extension)

      # Returns +true+ when +name+ is a String of the allowed characters
      # (WarpEngine::Names::PATTERN) no longer than #name_length.
      def folder_name_valid?(name)
        name.is_a?(String) && name.match?(WarpEngine::Names::PATTERN) && name.length <= name_length
      end

      # Returns the WarpEngine::Catalog::Selection of the directory: its platform, kinds
      # and listed statuses.
      def selection
        @selection ||= WarpEngine::Catalog::Selection.new(platforms: platforms, kinds: kinds, statuses: statuses)
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

      # Returns the Base#descriptor with the directory's +kinds+, +layout+, +index+
      # file and +urls+.
      def descriptor
        super.merge(kinds: kinds, layout: layout, index: IndexFile::NAME, urls: urls)
      end

      # Returns a one-line description, e.g.
      # <tt>c64 (directory: c64; package; flat; directories/C64)</tt>.
      def describe = "#{key} (#{type}: #{platform}; #{kinds.join(', ')}; #{layout}; #{path})"

      # Decides what the directory holds without touching the disk (Directory::Builder#plan).
      # Returns <tt>[entries, skipped]</tt>.
      def plan = builder.plan

      # Rebuilds the directory through Directory::Builder#sync!. Returns its
      # Directory::Builder::Result.
      def sync!(dry_run: false) = builder.sync!(dry_run: dry_run)

      # Returns the other directories of the same platform (a <tt>.D64</tt> directory
      # beside a <tt>.PRG</tt> one).
      def siblings
        Feeds.all.select { |feed| feed.is_a?(Directory) && feed.platform == platform && feed.key != key }
      end

      # Splits the +skipped+ of #plan (WarpEngine::Catalog::Selection::Skip list)
      # into those no directory of the platform holds and those a #siblings directory
      # holds. Returns <tt>[left_out, elsewhere]</tt>; +elsewhere+ pairs each
      # Skip with the key of the directory that holds its software.
      def split_skipped(skipped)
        return [ skipped, [] ] if skipped.empty?

        holders = siblings.each_with_object({}) do |sibling, held|
          sibling.plan.first.each { |entry| held[entry.software.id] ||= sibling.key }
        end
        elsewhere, left_out = skipped.partition { |skip| holders.key?(skip.software.id) }
        [ left_out, elsewhere.map { |skip| [ skip, holders[skip.software.id] ] } ]
      end

      # Returns the lines of the check: where the directory is served, every file
      # on it, every software another directory of the platform holds instead and
      # every software it leaves out.
      def report
        entries, skipped = plan
        left_out, elsewhere = split_skipped(skipped)
        urls.map { |url| "  served  #{url}" } +
          entries.map { |entry| "  ok      #{entry.file.ljust(name_length)} #{entry.version}  #{entry.software.name} (#{entry.kind})" } +
          elsewhere.map { |skip, holder| "  other   #{skip.software.name}: on the #{holder} directory" } +
          left_out.map { |skip| "  skipped #{skip}" }
      end

      private

      def builder = Builder.new(self)

      def check_extension!
        if folders?
          raise ConfigurationError, "#{key}: a folders directory takes no extension" if extension.present?
        elsif !extension.match?(EXTENSION_PATTERN)
          raise ConfigurationError, "#{key}: extension must look like .PRG: #{extension.inspect}"
        end
      end

      def check_preview!
        return unless preview
        raise ConfigurationError, "#{key}: unknown preview #{preview.inspect}" unless preview_renderer
        raise ConfigurationError, "#{key}: a folders directory takes no preview" if folders?
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

require "warp_engine/feeds/directory/index_file"
require "warp_engine/feeds/directory/layouts"
require "warp_engine/feeds/directory/preview"
require "warp_engine/feeds/directory/builder"
