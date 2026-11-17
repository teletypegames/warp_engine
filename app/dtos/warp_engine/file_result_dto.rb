module WarpEngine
  # What WarpEngine::FileService#show decided for a requested path: send a
  # local file, redirect to storage, show a folder's index page, send the
  # caller to where a flat-layout path moved, or report it missing.
  class FileResultDto
    # +type+ is <tt>:file</tt>, <tt>:redirect</tt>, <tt>:index</tt>,
    # <tt>:moved</tt> or <tt>:not_found</tt>; +path+ is the local file to send
    # (for <tt>:file</tt>), or the index page or the new place relative to the
    # storage (for <tt>:index</tt> and <tt>:moved</tt>); +url+ is
    # the redirect target (for <tt>:redirect</tt>).
    attr_reader :type, :path, :url

    # Builds a result of +type+ with an optional +path+ or +url+. The class
    # methods ::file, ::redirect, ::index and ::not_found are the usual way in.
    def initialize(type:, path: nil, url: nil)
      @type = type
      @path = path
      @url  = url
    end

    # Returns a <tt>:file</tt> result for the local file at +path+.
    def self.file(path)    = new(type: :file,      path: path)
    # Returns a <tt>:redirect</tt> result pointing at +url+.
    def self.redirect(url) = new(type: :redirect,  url: url)
    # Returns an <tt>:index</tt> result for the index page +path+ of a folder.
    def self.index(path)   = new(type: :index,     path: path)
    # Returns a <tt>:moved</tt> result for +path+, where a flat-layout path
    # is now.
    def self.moved(path)   = new(type: :moved,     path: path)
    # Returns a <tt>:not_found</tt> result.
    def self.not_found     = new(type: :not_found)
  end
end
