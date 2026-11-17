module WarpEngine
  module Build
    # Describes the platforms to the developer tools (an editor extension, a
    # scaffolder) through WarpEngine::PlatformDescriptionService: what each
    # one publishes and builds, its metadata and the JSON Schema of it, its web
    # runtimes, its pipeline marker and the host's tooling. Public, like the
    # pipeline preview.
    class PlatformsController < ApiController
      resource_description do
        short "Platform descriptions for developer tools"
      end

      api :GET, "/build/platforms", "Describe every platform"
      returns code: 200, desc: %(JSON: {"platforms": [description, ...]})
      # <tt>GET /build/platforms</tt>.
      #
      # Renders <tt>{ "platforms": [...] }</tt>, a description per platform
      # (WarpEngine::PlatformDescriptionService#describe).
      def index
        render json: { platforms: service.all }
      end

      api :GET, "/build/platforms/:name", "Describe one platform"
      param :name, String, required: true, desc: "Platform name, e.g. c64"
      returns code: 200, desc: "JSON: the platform's description"
      error code: 404, desc: "Unknown platform"
      # <tt>GET /build/platforms/:name</tt>.
      #
      # Renders the description of the platform +name+, or 404 when there is
      # none.
      def show
        description = service.find(params[:name])
        return not_found if description.nil?

        render json: description
      end

      api :GET, "/build/platforms/:name/metadata-schema", "The JSON Schema of a platform's metadata"
      param :name, String, required: true, desc: "Platform name, e.g. c64"
      returns code: 200, desc: "JSON Schema (application/schema+json)"
      error code: 404, desc: "Unknown platform"
      # <tt>GET /build/platforms/:name/metadata-schema</tt>.
      #
      # Renders the JSON Schema of the metadata of the platform +name+
      # (WarpEngine::PlatformDescriptionService#metadata_schema) as
      # <tt>application/schema+json</tt>, or 404 when there is none.
      def metadata_schema
        schema = service.metadata_schema(params[:name])
        return not_found if schema.nil?

        render json: schema, content_type: "application/schema+json"
      end

      private

      def service = WarpEngine::PlatformDescriptionService.new

      def not_found
        render json: { error: "Unknown platform" }, status: :not_found
      end
    end
  end
end
