module WarpEngine
  class FileService
    # Lazy: a container path csak az első használatkor kötelező, boot/teszt közben nem.
    def self.base_path
      Pathname.new(WarpEngine.config.file_container_path).realpath
    end

    def show(input)
      full_path = base_path.join(input.path.to_s)
      return FileResultDto.not_found unless safe_path?(full_path)

      if File.directory?(full_path)
        index_path = full_path.join("index.html")
        return FileResultDto.not_found unless File.file?(index_path)
        return FileResultDto.redirect("/file/#{input.path.to_s.chomp("/")}/index.html")
      end

      if File.file?(full_path)
        FileResultDto.file(full_path)
      else
        FileResultDto.not_found
      end
    end

    private

    def base_path
      @base_path ||= self.class.base_path
    end

    def safe_path?(path)
      File.exist?(path) && Pathname.new(path).realpath.to_s.start_with?(base_path.to_s)
    end
  end
end
