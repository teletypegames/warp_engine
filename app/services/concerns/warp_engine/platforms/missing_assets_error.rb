module WarpEngine
  module Platforms
    # Raised by Updatable#update when an upload lacks a kind the platform lists in
    # +required_kinds+.
    class MissingAssetsError < StandardError
      # The missing asset kinds, as strings.
      attr_reader :kinds

      # [versioned] the <tt>name-version</tt> of the upload, used in the message
      # [kinds]     the missing asset kinds
      def initialize(versioned, kinds)
        @kinds = kinds
        super("#{versioned}: no #{kinds.join(', ')} uploaded, which the platform requires")
      end
    end
  end
end
