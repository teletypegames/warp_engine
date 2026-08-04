module WarpEngine
  class FileResultDto
    attr_reader :type, :path, :url

    def initialize(type:, path: nil, url: nil)
      @type = type
      @path = path
      @url  = url
    end

    def self.file(path)    = new(type: :file,      path: path)
    def self.redirect(url) = new(type: :redirect,  url: url)
    def self.not_found     = new(type: :not_found)
  end
end
