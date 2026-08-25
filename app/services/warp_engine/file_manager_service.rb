module WarpEngine
  class FileManagerService

    def base_path
      @base_path ||= Pathname.new(WarpEngine.config.file_container_path)
    end

    def list(relative_path = "")
      full = safe_path!(relative_path)
      raise ArgumentError, "Not a directory" unless full.directory?

      entries = full.children.sort_by { |c| [ c.directory? ? 0 : 1, c.basename.to_s.downcase ] }
      entries.map do |child|
        stat = child.stat
        {
          name:  child.basename.to_s,
          path:  child.relative_path_from(base_path).to_s,
          type:  child.directory? ? :directory : :file,
          size:  child.directory? ? nil : stat.size,
          mtime: stat.mtime
        }
      end
    end

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

    def delete(relative_path)
      full = safe_path!(relative_path)
      raise ArgumentError, "Cannot delete root" if full == base_path

      if full.directory?
        full.rmdir
      else
        full.delete
      end
    end

    def rename(relative_path, new_name)
      full = safe_path!(relative_path)
      raise ArgumentError, "Cannot rename root" if full == base_path

      safe_name = sanitize_name(new_name)
      new_full = full.parent.join(safe_name)
      ensure_within_base!(new_full)

      full.rename(new_full)
      new_full.relative_path_from(base_path).to_s
    end

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

    def ensure_within_base!(path)
      raise ArgumentError, "Path escape" unless path.to_s.start_with?(base_path.to_s)
    end

    def safe_path!(relative_path)
      cleaned = relative_path.to_s.gsub("..", "").squeeze("/").gsub(%r{^/|/$}, "")
      full = base_path.join(cleaned)
      resolved = full.exist? ? full.realpath : full.cleanpath
      unless resolved.to_s.start_with?(base_path.to_s)
        raise ArgumentError, "Path traversal detected"
      end
      resolved
    end

    def sanitize_name(name)
      name.to_s.gsub("..", "").gsub("/", "").gsub("\\", "").strip.tap do |n|
        raise ArgumentError, "Invalid name" if n.blank?
      end
    end
  end
end
