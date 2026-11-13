module WarpEngine
  # The base class of every error the engine raises on purpose. A host can
  # rescue it to catch them all; each part of the engine raises a subclass.
  class Error < StandardError; end

  # A host configuration the engine cannot run with: a shelf, an outlet, a
  # platform or the Admin API set up wrongly. WarpEngine::Outlets.validate!
  # raises it at boot.
  class ConfigurationError < Error; end

  # Raised when the access policy denies a download or a file; the API
  # controllers render it as 403.
  class AccessDenied < Error; end

  # Platform support; see WarpEngine::Platform.
  module Platforms
    # Raised by a publish when the upload lacks a kind the platform requires.
    class MissingAssetsError < WarpEngine::Error
      # The missing kinds, as strings.
      attr_reader :kinds

      # Creates the error for the upload +versioned+ (<tt>name-version</tt>)
      # missing +kinds+.
      def initialize(versioned, kinds)
        @kinds = kinds
        super("#{versioned}: no #{kinds.join(', ')} uploaded, which the platform requires")
      end
    end
  end
end
