module WarpEngine
  # Where the files of a release live in the file container: every release
  # has its own folder, <tt><name>/<version>/</tt>. The uploaded files keep
  # their names (<tt><name>-<version>.prg</tt>, ...), so a download is named
  # as before; a kind the engine unpacks (WarpEngine::AssetKind#unpacked?)
  # becomes a folder named after the kind (<tt>html/</tt>, <tt>docs/</tt>).
  #
  # Before 3.4 the container was flat: every file and unpacked folder sat in
  # its root, named <tt><name>-<version>...</tt>. #legacy_parts tells which
  # release such a name belonged to; WarpEngine::ReleaseLayoutService moves
  # the old files and answers the old URLs.
  module ReleaseLayout
    module_function

    # Returns the folder of the release +version+ of the software +name+,
    # relative to the file container (<tt>name/version</tt>).
    def directory(name, version) = File.join(name.to_s, version.to_s)

    # Returns the absolute folder of the release +version+ of +name+.
    def absolute_directory(name, version) = File.join(WarpEngine.config.file_container_path.to_s, directory(name, version))

    # Returns the names of the root folders of the file container that are no
    # software's: the runtimes (WarpEngine::Runtime::ROOT) and the first
    # folder of every feed with a +path+ (the directories).
    def reserved
      roots = WarpEngine::Feeds.static.filter_map do |feed|
        feed.path.to_s.split("/").find(&:present?) if feed.respond_to?(:path)
      end
      ([ WarpEngine::Runtime::ROOT ] + roots).uniq
    end

    # Returns +true+ when +name+ cannot be a software's folder (#reserved).
    def reserved?(name) = reserved.include?(name.to_s)

    # Splits +entry+, a name of the flat layout, into the release it belonged
    # to and its name in that release's folder.
    #
    # [entry]  a root entry of the old layout, e.g. <tt>game-1.0.prg</tt>
    # [owners] a Hash of <tt>name-version</tt> prefix to the
    #          <tt>[name, version]</tt> it stands for (#owners); the longest
    #          prefix that +entry+ starts with wins
    #
    # Returns <tt>[name, version, new_name]</tt>, or +nil+ when +entry+ is no
    # release's. An unpacked folder (<tt>game-1.0</tt>, <tt>game-1.0-docs</tt>)
    # gets its kind's name, a file keeps its own.
    def legacy_parts(entry, owners)
      entry = entry.to_s
      prefix = owners.keys.select { |versioned| owns?(entry, versioned) }.max_by(&:length)
      return nil if prefix.nil?

      name, version = owners.fetch(prefix)
      rest = entry.delete_prefix(prefix)
      unpacked = WarpEngine::AssetKinds::ALL.each_value.find { |kind| kind.unpacked? && kind.unpack_to == rest }
      [ name, version, unpacked ? unpacked.name : entry ]
    end

    # Returns the owners #legacy_parts takes: <tt>name-version</tt> of every
    # <tt>[name, version]</tt> in +releases+, plus the prefix of every
    # +aliases+ entry (an asset name of the flat layout to its release's
    # <tt>[name, version]</tt>), so the files of a renamed software, still
    # named after its old name, go with its release.
    def owners(releases, aliases = {})
      found = releases.to_h { |name, version| [ "#{name}-#{version}", [ name, version ] ] }
      aliases.each do |asset_name, release|
        prefix = legacy_prefix(asset_name)
        found[prefix] ||= release if prefix.present?
      end
      found
    end

    # Returns the <tt>name-version</tt> part of +asset_name+, an asset of the
    # flat layout: without the suffix of its kind (<tt>-win-x64.zip</tt>,
    # <tt>-docs</tt>, ...), else without its extension.
    def legacy_prefix(asset_name)
      asset_name = asset_name.to_s
      tails = WarpEngine::AssetKinds::ALL.each_value.flat_map { |kind| [ kind.suffix, kind.unpack_to ] }.compact_blank
      tail = tails.select { |suffix| asset_name.end_with?(suffix) }.max_by(&:length)
      return asset_name.delete_suffix(tail) if tail

      extension = File.extname(asset_name)
      extension.match?(/\A\.[A-Za-z0-9]+\z/) && !extension.match?(/\A\.\d+\z/) ? asset_name.delete_suffix(extension) : asset_name
    end

    # Returns +true+ when +entry+ is +versioned+ itself or starts with it and
    # a dot or a dash.
    def owns?(entry, versioned) = entry == versioned || entry.start_with?("#{versioned}.", "#{versioned}-")
  end
end
