module WarpEngine
  module Build
    # Woodpecker configuration-extension endpoint: on every pipeline start the
    # CI server POSTs the repo's marker file and receives the platform's full
    # pipeline YAML. GET renders the same thing as a preview.
    class ConfigsController < ApiController
      resource_description do
        short "Woodpecker CI pipeline configs"
      end

      api :GET, "/build/config", "Preview the generated pipeline config for a platform"
      param :platform, String, required: true, desc: "Platform (a configured ci_platforms key, e.g. tic80)"
      param :name, String, required: false, desc: "Software name substituted into the pipeline (default: example)"
      returns code: 200, desc: "Pipeline YAML (text/yaml)"
      error code: 404, desc: "Unknown platform"
      def show
        yaml = render_config(platform: params[:platform], name: params[:name].presence || "example")
        return render json: { error: "Unknown platform" }, status: :not_found if yaml.nil?

        render plain: yaml, content_type: "text/yaml"
      end

      api :POST, "/build/config", "Woodpecker configuration extension endpoint"
      description <<~DESC
        Called by the Woodpecker server on every pipeline start (httpsig-signed request).
        If the repo's .woodpecker.yaml is a marker (has a `platform:` key), responds with
        the generated pipeline; otherwise responds 204 so the repo's own config runs.
      DESC
      returns code: 200, desc: %(JSON: {"configs": [{"name": ..., "data": "<pipeline YAML>"}]})
      returns code: 204, desc: "Not a marker config — keep the repo's own configuration"
      error code: 403, desc: "Missing or invalid request signature"
      error code: 422, desc: "Marker requests an unknown platform"
      def create
        unless WarpEngine::CiSignatureVerifier.new(request).valid?
          return render json: { error: "Invalid signature" }, status: :forbidden
        end

        marker = find_marker
        return head :no_content if marker.nil?

        platform = marker["platform"].to_s
        name     = marker["name"].presence || repo_name
        yaml     = render_config(platform: platform, name: name)
        if yaml.nil?
          return render json: { error: "Unknown platform: #{platform}" }, status: :unprocessable_entity
        end

        render json: { configs: [ { name: platform, data: yaml } ] }
      end

      private

      def render_config(platform:, name:)
        WarpEngine::CiConfigService.new.render(
          platform:      platform,
          name:          name,
          update_server: WarpEngine.config.ci_update_server.presence || request.base_url
        )
      end

      # The first submitted config that parses as a marker (Hash with a `platform`
      # key). The docs call the key "configuration", the example-config-service
      # uses "configs" — accept both.
      def find_marker
        configs = params[:configuration].presence || params[:configs].presence || []
        configs.each do |config|
          data = config[:data].to_s
          parsed = begin
            YAML.safe_load(data)
          rescue Psych::Exception
            nil
          end
          return parsed if parsed.is_a?(Hash) && parsed.key?("platform")
        end
        nil
      end

      def repo_name
        params.dig(:repo, :name).to_s
      end
    end
  end
end
