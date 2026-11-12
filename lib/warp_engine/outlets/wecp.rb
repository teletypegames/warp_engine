module WarpEngine
  module Outlets
    # The engine's own outlet: the WarpEngine Catalog Protocol, the JSON
    # catalog API under <tt>/api</tt> with the files under <tt>/file</tt> and
    # <tt>/api/download</tt>. It is always on and has no configuration; its
    # controllers (WarpEngine::Api::SoftwareController and the rest) decide
    # visibility per caller through the access policy, so it is the only
    # outlet that knows a subject, a sign-in and a gated title.
    class Wecp < Base
      # Returns +wecp+.
      def self.type_name = "wecp"

      # Creates the outlet under the key +wecp+.
      def initialize
        super("wecp")
      end

      # Returns the Base#descriptor with the API shape +version+
      # (WarpEngine::API_VERSION).
      def descriptor = super.merge(version: WarpEngine::API_VERSION)

      # Returns no lines: the catalog API lists every visible title.
      def report = []
    end
  end
end
