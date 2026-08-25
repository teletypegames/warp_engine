module WarpEngine
  module Build
    class ConfigsController < ApiController
      resource_description do
        short "CI pipeline configs"
      end

      api :GET, "/build/config", "Preview the generated pipeline config for a platform"
      param :platform, String, required: true, desc: "Platform (a platform the CI adapter serves, e.g. tic80)"
      param :name, String, required: false, desc: "Software name substituted into the pipeline (default: example)"
      returns code: 200, desc: "Pipeline YAML (text/yaml)"
      error code: 404, desc: "Unknown platform"
      def show
        config = render_config(platform: params[:platform], name: params[:name].presence || "example")
        return render json: { error: "Unknown platform" }, status: :not_found if config.nil?

        render plain: config, content_type: "text/yaml"
      end

      api :POST, "/build/config", "CI configuration extension endpoint"
      description <<~DESC
        Called by the CI server on every pipeline start (a signed request the CI adapter
        verifies). If the repo's config is a marker (has a `platform:` key), responds with
        the generated pipeline; otherwise responds 204 so the repo's own config runs.
      DESC
      returns code: 200, desc: %(JSON: the adapter's config response — for Woodpecker {"configs": [{"name": ..., "data": "<pipeline YAML>"}]})
      returns code: 204, desc: "Not a marker config — keep the repo's own configuration"
      error code: 403, desc: "Missing or invalid request signature"
      error code: 422, desc: "Marker requests an unknown platform"
      def create
        unless ci.verify_config_request(request)
          return render json: { error: "Invalid signature" }, status: :forbidden
        end

        marker = ci.config_marker(params)
        return head :no_content if marker.nil?

        config = render_config(platform: marker[:platform], name: marker[:name])
        if config.nil?
          return render json: { error: "Unknown platform: #{marker[:platform]}" }, status: :unprocessable_entity
        end

        render json: ci.config_response(platform: marker[:platform], config: config)
      end

      private

      def ci
        WarpEngine.ci
      end

      def render_config(platform:, name:)
        ci.pipeline_config(
          platform:      platform,
          name:          name,
          update_server: ci.update_server.presence || request.base_url
        )
      end
    end
  end
end
