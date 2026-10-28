module WarpEngine
  # What WarpEngine::FileService#show decided for a requested path: send a
  # local file, redirect, or report it missing.
  class FileResultDto
    # +type+ is <tt>:file</tt>, <tt>:redirect</tt> or <tt>:not_found</tt>; +path+
    # is the local file to send (for <tt>:file</tt>); +url+ is the redirect
    # target (for <tt>:redirect</tt>).
    attr_reader :type, :path, :url

    # Builds a result of +type+ with an optional +path+ or +url+. The class
    # methods ::file, ::redirect and ::not_found are the usual way in.
    def initialize(type:, path: nil, url: nil)
      @type = type
      @path = path
      @url  = url
    end

    # Returns a <tt>:file</tt> result for the local file at +path+.
    def self.file(path)    = new(type: :file,      path: path)
    # Returns a <tt>:redirect</tt> result pointing at +url+.
    def self.redirect(url) = new(type: :redirect,  url: url)
    # Returns a <tt>:not_found</tt> result.
    def self.not_found     = new(type: :not_found)
  end
end
