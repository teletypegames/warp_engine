module WarpEngine
  module Outlets
    # The engine's own outlet: the WarpEngine Catalog Protocol, the JSON
    # catalog API under <tt>/api</tt> with the files under <tt>/file</tt> and
    # <tt>/api/download</tt>. It is always on and takes no configuration. It is
    # the one outlet without a WarpEngine::Catalog::Offer: its controllers
    # (WarpEngine::Api::SoftwareController and the rest) decide visibility per
    # caller through the access policy, so it alone knows a subject, a sign-in
    # and a gated title.
    #
    # Endpoints (drawn by Wecp.draw_routes):
    #
    # [<tt>GET /api/service</tt>]                 the service descriptor
    # [<tt>POST /api/auth/device</tt>, <tt>POST /api/auth/device/token</tt>, <tt>DELETE /api/auth/token</tt>]
    #                                             the device sign-in
    # [<tt>GET /api/software</tt>]                the catalog, with +highlighted+, +facets+ and +vocabulary+ beside it
    # [<tt>GET /api/download?path=</tt>]          a file, counted
    # [<tt>GET /file/*path</tt>]                  a file or a web build
    # [<tt>GET /play/:name/:version(/:binding)</tt>] the web player page of a release in a runtime
    class Wecp < Base
      include Served

      class << self
        # Returns +wecp+.
        def type_name = "wecp"

        # Draws the catalog API into the engine's routes (+mapper+). The
        # routes take no constraint: the outlet is always on.
        def draw_routes(mapper)
          mapper.namespace :api do
            mapper.get "service", to: "service#show"

            mapper.namespace :auth do
              mapper.post   "device",       to: "devices#create"
              mapper.post   "device/token", to: "device_tokens#create"
              mapper.delete "token",        to: "tokens#destroy"
            end

            mapper.get "software",             to: "software#index"
            mapper.get "software/highlighted", to: "software_highlighted#show"
            mapper.get "software/facets",      to: "software_facets#show"
            mapper.get "software/vocabulary",  to: "software_vocabulary#show"
            mapper.get "download",             to: "downloads#show"
          end

          mapper.get "file/*path", to: "files#show", format: false, as: :file
          mapper.get "play/:name/:version(/:binding)", to: "play#show", format: false, as: :play,
                                                       constraints: { name: %r{[^/]+}, version: %r{[^/]+}, binding: %r{[^/]+} }
          mapper.get "play-preview/:platform(/:binding)", to: "play#preview", format: false, as: :play_preview,
                                                          constraints: { platform: %r{[^/]+}, binding: %r{[^/]+} }
        end
      end

      # Creates the outlet under the key +wecp+; it has no options.
      def initialize(key = self.class.type_name, options = {})
        super
      end

      # Returns the Base#descriptor with the API shape +version+
      # (WarpEngine::API_VERSION).
      def descriptor = super.merge(version: WarpEngine::API_VERSION)

      # Returns no lines: the catalog API lists every visible title.
      def report = []
    end
  end
end
