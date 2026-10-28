require "warp_engine/access_denied"

module WarpEngine
  # Serves the file container under <tt>/file/</tt>: a file through the access
  # policy, a directory as a redirect to its <tt>index.html</tt>.
  class FileService
    include AccessPolicyGuard

    # Answers the path of +input+ (an object with +path+, relative to the storage)
    # for +subject+ (+nil+ when anonymous).
    #
    # Returns a WarpEngine::FileResultDto: a redirect to
    # <tt>/file/<dir>/index.html</tt> for a directory that has one, the file (a
    # local path or a storage redirect) for a file, not found otherwise. Raises
    # WarpEngine::AccessDenied when the access policy refuses the file.
    def show(input, subject: nil)
      relative = input.path.to_s

      if storage.directory?(relative)
        index = File.join(relative.chomp("/"), "index.html")
        return FileResultDto.not_found unless storage.file?(index)

        return FileResultDto.redirect("/file/#{index}")
      end

      return FileResultDto.not_found unless storage.file?(relative)

      authorize!(relative, subject)

      to_result(storage.locate(relative, filename: File.basename(relative)))
    end

    private

    def authorize!(relative, subject)
      return WarpEngine::Access::Grant::OPEN if WarpEngine::AccessPolicy.open?

      asset = WarpEngine::ReleaseAsset.for_relative_path(relative)
      authorize_download!(asset: asset, subject: subject, request: nil)
    end

    def storage
      WarpEngine.storage
    end

    def to_result(location)
      location.redirect? ? FileResultDto.redirect(location.url) : FileResultDto.file(location.path)
    end
  end
end
