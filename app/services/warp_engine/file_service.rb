module WarpEngine
  class FileService
    # Lazy: a container path csak az első használatkor kötelező, boot/teszt közben nem.
    def self.base_path
      Pathname.new(WarpEngine.config.file_container_path).realpath
    end

    # A fájlok helyét a storage adapter adja (alapból :local, azaz a lemez) —
    # így a host az objektumtárból is kiszolgálhat anélkül, hogy az engine-t
    # patchelné. Lásd WarpEngine::Storage.
    def show(input)
      relative = input.path.to_s

      if storage.directory?(relative)
        index = File.join(relative.chomp("/"), "index.html")
        return FileResultDto.not_found unless storage.file?(index)

        return FileResultDto.redirect("/file/#{index}")
      end

      return FileResultDto.not_found unless storage.file?(relative)

      to_result(storage.locate(relative, filename: File.basename(relative)))
    end

    private

    def storage
      WarpEngine.storage
    end

    def to_result(location)
      location.redirect? ? FileResultDto.redirect(location.url) : FileResultDto.file(location.path)
    end
  end
end
