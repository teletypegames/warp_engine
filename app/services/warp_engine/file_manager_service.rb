module WarpEngine
  # File browser of the file container (<tt>WarpEngine.config.file_container_path</tt>)
  # for the admin: lists, uploads, renames, deletes and creates entries. Every
  # path is relative to the container and confined to it; a path or name that
  # would leave it raises ArgumentError.
  class FileManagerService
    # The file container directory, as a Pathname.
    def base_path
      @base_path ||= Pathname.new(WarpEngine.config.file_container_path)
    end

    # Lists the directory +relative_path+, directories first, then by name.
    #
    # [relative_path]        the directory, relative to #base_path (default the root)
    # [with_download_counts] also count the WarpEngine::Download records of every file
    #
    # Returns an Array of Hashes with +name+, +path+ (relative), +type+
    # (<tt>:directory</tt> or <tt>:file</tt>), +size+ (+nil+ for directories),
    # +mtime+ and, when asked, +downloads+. Raises ArgumentError when the path is
    # not a directory or leaves the container.
    def list(relative_path = "", with_download_counts: false)
      full = safe_path!(relative_path)
      raise ArgumentError, "Not a directory" unless full.directory?

      children = full.children.sort_by { |c| [ c.directory? ? 0 : 1, c.basename.to_s.downcase ] }
      entries = children.map do |child|
        stat = child.stat
        {
          name:  child.basename.to_s,
          path:  child.relative_path_from(base_path).to_s,
          type:  child.directory? ? :directory : :file,
          size:  child.directory? ? nil : stat.size,
          mtime: stat.mtime
        }
      end
      with_download_counts ? add_download_counts(entries) : entries
    end

    # Writes +uploaded_file+ (an uploaded file with +original_filename+, +size+
    # and +to_io+) into the directory +relative_dir+ under its sanitized name,
    # overwriting a file of that name. Returns the new file's relative path.
    # Raises ArgumentError when the file is larger than
    # <tt>WarpEngine.config.max_upload_size</tt>, the target is not a directory, or
    # the name is empty or unsafe.
    def upload(relative_dir, uploaded_file)
      max = WarpEngine.config.max_upload_size
      raise ArgumentError, "File too large (max #{max / (1024 * 1024)}MB)" if uploaded_file.size > max
      dir = safe_path!(relative_dir)
      raise ArgumentError, "Not a directory" unless dir.directory?

      safe_name = sanitize_name(uploaded_file.original_filename)
      target = dir.join(safe_name)
      ensure_within_base!(target)

      IO.copy_stream(uploaded_file.to_io, target.to_s)
      target.relative_path_from(base_path).to_s
    end

    # Deletes the file or the empty directory at +relative_path+. Raises
    # ArgumentError for the root, and Errno::ENOTEMPTY for a directory that is not empty.
    def delete(relative_path)
      full = safe_path!(relative_path)
      raise ArgumentError, "Cannot delete root" if full == base_path

      if full.directory?
        full.rmdir
      else
        full.delete
      end
    end

    # Renames the entry at +relative_path+ to +new_name+ (sanitized) in the same
    # directory. Returns the new relative path. Raises ArgumentError for the root
    # or an invalid name.
    def rename(relative_path, new_name)
      full = safe_path!(relative_path)
      raise ArgumentError, "Cannot rename root" if full == base_path

      safe_name = sanitize_name(new_name)
      new_full = full.parent.join(safe_name)
      ensure_within_base!(new_full)

      full.rename(new_full)
      new_full.relative_path_from(base_path).to_s
    end

    # Creates the directory +folder_name+ (sanitized) inside +relative_path+.
    # Returns its relative path. Raises ArgumentError when the parent is not a
    # directory or the name is invalid, and Errno::EEXIST when it exists.
    def mkdir(relative_path, folder_name)
      parent = safe_path!(relative_path)
      raise ArgumentError, "Not a directory" unless parent.directory?

      safe_name = sanitize_name(folder_name)
      new_dir = parent.join(safe_name)
      ensure_within_base!(new_dir)

      new_dir.mkdir
      new_dir.relative_path_from(base_path).to_s
    end

    private

    def add_download_counts(entries)
      paths = entries.reject { |e| e[:type] == :directory }.map { |e| e[:path] }
      counts = paths.any? ? Download.where(file_path: paths).group(:file_path).count : {}
      entries.map { |e| e[:type] == :directory ? e : e.merge(downloads: counts[e[:path]] || 0) }
    end

    def ensure_within_base!(path)
      raise ArgumentError, "Path escape" unless path.to_s.start_with?(base_path.to_s)
    end

    # Resolves +relative_path+ under #base_path after stripping <tt>..</tt> and
    # outer slashes. Raises ArgumentError when the result is outside the container.
    def safe_path!(relative_path)
      cleaned = relative_path.to_s.gsub("..", "").squeeze("/").gsub(%r{^/|/$}, "")
      full = base_path.join(cleaned)
      resolved = full.exist? ? full.realpath : full.cleanpath
      unless resolved.to_s.start_with?(base_path.to_s)
        raise ArgumentError, "Path traversal detected"
      end
      resolved
    end

    # Strips <tt>..</tt>, slashes and backslashes from +name+. Raises ArgumentError
    # when nothing is left.
    def sanitize_name(name)
      name.to_s.gsub("..", "").gsub("/", "").gsub("\\", "").strip.tap do |n|
        raise ArgumentError, "Invalid name" if n.blank?
      end
    end
  end
end
