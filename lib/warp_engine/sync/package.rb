require "zip"
require "tmpdir"

module WarpEngine
  module Sync
    # What one push carries, whatever the WarpEngine::Sync::Transport: the
    # +release+, its +software+ and +platform+ (a WarpEngine::Platform), the
    # +files+ to send (PackageFile values) and the +commit+ it was built of.
    #
    # The files are those the CI uploaded for the release: the upload names
    # of the platform's kinds the filter lets go, and
    # <tt>name-version.metadata.json</tt> on a JSON platform. A file missing
    # under its upload name (a software renamed since) is taken from the path
    # its WarpEngine::ReleaseAsset records, the metadata from the folder's
    # <tt>*-version.metadata.json</tt>; a kind served unpacked whose zip is
    # gone is zipped again from its folder. Every file carries the name the
    # other side expects.
    Package = ::Data.define(:release, :software, :platform, :files, :commit) do
      # Returns the software name.
      def name = software.name

      # Returns the version.
      def version = release.version

      # Returns <tt>name-version</tt>, the prefix of every file name.
      def versioned = "#{name}-#{version}"

      # Returns the asset kinds the files bring (the metadata has none).
      def kinds = files.filter_map(&:kind)

      # Returns +true+ when there is nothing to send.
      def empty? = files.empty?

      # Returns the bytes of every file.
      def bytes = files.sum { |file| File.size(file.path) }

      # Builds the Package of +release+ through +filter+ (a
      # WarpEngine::Sync::Filter, which chooses the kinds), in a temporary
      # folder for the files it zips again, and yields it; the folder is
      # removed afterwards. Returns what the block returns.
      def self.build(release, filter)
        software = release.software
        platform = WarpEngine::Platform.find!(software.platform)
        upload = Publish::Upload.new(name: software.name, version: release.version,
                                     root: WarpEngine::ReleaseLayout.absolute_directory(software.name, release.version))
        assets = recorded_paths(release)
        Dir.mktmpdir("warp-engine-sync") do |tmp|
          files = filter.kind_specs(platform).filter_map { |spec| file_of(spec, upload, assets, tmp) }
          metadata = metadata_of(upload) if platform.definition.metadata.to_s == "json"
          files << PackageFile.new(path: metadata, name: "#{upload.versioned}.metadata.json", kind: nil) if metadata
          yield new(release: release, software: software, platform: platform, files: files.uniq(&:name),
                    commit: release.try(:commit_sha))
        end
      end

      # Returns the kinds +filter+ lets go that +release+ has a file for,
      # without zipping anything.
      def self.kinds_of(release, filter)
        software = release.software
        platform = WarpEngine::Platform.find!(software.platform)
        upload = Publish::Upload.new(name: software.name, version: release.version,
                                     root: WarpEngine::ReleaseLayout.absolute_directory(software.name, release.version))
        assets = recorded_paths(release)
        filter.kind_specs(platform).select { |spec| source_of(spec, upload, assets) }.map(&:name)
      end

      # Returns the path of each kind as the release's assets record it.
      def self.recorded_paths(release)
        assets = release.release_assets
        assets = assets.kept if assets.respond_to?(:kept)
        assets.to_h { |asset| [ asset.kind.to_s, asset.path.to_s ] }
      end

      # Returns where the file (or unpacked folder) of the kind +spec+ is, or +nil+.
      def self.source_of(spec, upload, assets)
        expected = upload.path(spec.upload_name(upload.versioned))
        return expected if File.file?(expected)

        recorded = assets[spec.name]
        if spec.kind.unpacked?
          return [ upload.path(spec.asset_name(upload.versioned)), recorded ].compact.find { |path| File.directory?(path) }
        end
        recorded if recorded && File.file?(recorded)
      end

      # Returns the PackageFile of the kind +spec+, zipping a folder into +tmp+, or +nil+.
      def self.file_of(spec, upload, assets, tmp)
        source = source_of(spec, upload, assets)
        return nil if source.nil?

        name = spec.upload_name(upload.versioned)
        path = File.file?(source) ? source : zip_folder(source, File.join(tmp, name))
        PackageFile.new(path: path, name: name, kind: spec.name)
      end

      # Returns the metadata file of +upload+: its own name, else the
      # folder's <tt>*-version.metadata.json</tt>, else +nil+.
      def self.metadata_of(upload)
        expected = upload.path("#{upload.versioned}.metadata.json")
        return expected if File.file?(expected)

        Dir.glob(File.join(upload.root, "*-#{upload.version}.metadata.json")).min
      end

      # Zips the folder +folder+ into +target+ and returns +target+.
      def self.zip_folder(folder, target)
        Zip::File.open(target, Zip::File::CREATE) do |zip|
          Dir.glob("**/*", File::FNM_DOTMATCH, base: folder).sort.each do |entry|
            next if [ ".", ".." ].include?(File.basename(entry))

            source = File.join(folder, entry)
            File.directory?(source) ? zip.mkdir(entry) : zip.add(entry, source)
          end
        end
        target
      end
    end

    # One file of a WarpEngine::Sync::Package: where it is (+path+), the
    # +name+ it is sent under and the asset +kind+ it is (+nil+ for the metadata).
    PackageFile = ::Data.define(:path, :name, :kind)
  end
end
