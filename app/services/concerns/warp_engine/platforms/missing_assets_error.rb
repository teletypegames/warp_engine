module WarpEngine
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
