module WarpEngine
  module Platforms
    class MissingAssetsError < StandardError
      attr_reader :kinds

      def initialize(versioned, kinds)
        @kinds = kinds
        super("#{versioned}: no #{kinds.join(', ')} uploaded, which the platform requires")
      end
    end
  end
end
