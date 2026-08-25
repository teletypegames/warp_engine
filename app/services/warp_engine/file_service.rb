require "warp_engine/access_denied"

module WarpEngine
  class FileService

    include AccessPolicyGuard

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
