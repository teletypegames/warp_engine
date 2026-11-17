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
    # folder of every outlet with a +path+ (the shelves).
    def reserved
      roots = WarpEngine::Outlets.materialized.filter_map do |outlet|
        outlet.path.to_s.split("/").find(&:present?) if outlet.respond_to?(:path)
      end
      ([ WarpEngine::Runtime::ROOT ] + roots).uniq
    end

    # Returns +true+ when +name+ cannot be a software's folder (#reserved).
    def reserved?(name) = reserved.include?(name.to_s)

    # Splits +entry+, a name of the flat layout, into the release it belonged
    # to and its name in that release's folder.
    #
    # [entry]    a root entry of the old layout, e.g. <tt>game-1.0.prg</tt>
    # [releases] the candidate <tt>[name, version]</tt> pairs; the longest
    #            <tt>name-version</tt> that +entry+ starts with wins
    #
    # Returns <tt>[name, version, new_name]</tt>, or +nil+ when +entry+ is no
    # release's. An unpacked folder (<tt>game-1.0</tt>, <tt>game-1.0-docs</tt>)
    # gets its kind's name, a file keeps its own.
    def legacy_parts(entry, releases)
      entry = entry.to_s
      match = releases.select { |name, version| owns?(entry, "#{name}-#{version}") }
                      .max_by { |name, version| "#{name}-#{version}".length }
      return nil if match.nil?

      name, version = match
      rest = entry.delete_prefix("#{name}-#{version}")
      unpacked = WarpEngine::AssetKinds::ALL.each_value.find { |kind| kind.unpacked? && kind.unpack_to == rest }
      [ name, version, unpacked ? unpacked.name : entry ]
    end

    # Returns +true+ when +entry+ is +versioned+ itself or starts with it and
    # a dot or a dash.
    def owns?(entry, versioned) = entry == versioned || entry.start_with?("#{versioned}.", "#{versioned}-")
  end
end
