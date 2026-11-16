module WarpEngine
  # Serves the file container under <tt>/file/</tt>: a file through the access
  # policy (an installed runtime's file, under <tt>_runtimes/</tt>, without it),
  # a directory as its <tt>index.html</tt> page.
  class FileService
    include AccessPolicyGuard

    # Answers +path+ (relative to the storage) for +subject+ (+nil+ when
    # anonymous).
    #
    # Returns a WarpEngine::FileResultDto: an <tt>:index</tt> result naming
    # <tt>dir/index.html</tt> for a directory that has one (the controller
    # turns it into a URL), the file (a local path or a storage redirect) for a
    # file, not found otherwise. Raises WarpEngine::AccessDenied when the
    # access policy refuses the file.
    def show(path:, subject: nil)
      relative = path.to_s

      if storage.directory?(relative)
        index = File.join(relative.chomp("/"), "index.html")
        return FileResultDto.not_found unless storage.file?(index)

        return FileResultDto.index(index)
      end

      return FileResultDto.not_found unless storage.file?(relative)

      authorize!(relative, subject)

      to_result(storage.locate(relative, filename: File.basename(relative)))
    end

    private

    def authorize!(relative, subject)
      return WarpEngine::Access::Grant::OPEN if WarpEngine::AccessPolicy.open? || runtime_file?(relative)

      authorize_download!(asset: WarpEngine::ReleaseAsset.for_relative_path(relative), subject: subject)
    end

    def storage
      WarpEngine.storage
    end

    def runtime_file?(relative) = relative.start_with?("#{WarpEngine::Runtime::ROOT}/")

    def to_result(location)
      location.redirect? ? FileResultDto.redirect(location.url) : FileResultDto.file(location.path)
    end
  end
end
