module WarpEngine
  module Build
    class PublishController < ApiController
      include UpdateAuthentication

      resource_description do
        short "Build release publishing"
      end

      api :POST, "/build/publish", "Register an uploaded build as a release"
      header "X-Update-Secret", "Shared secret or application token (update scope)", required: true
      param :name, String, required: true, desc: "Software name"
      param :platform, String, required: true, desc: "Platform (tic80, love, ebitengine, c64, godot, bevy, phaser)"
      param :version, String, required: true, desc: "Version string"
      returns code: 200, desc: "JSON with the published name/platform/version"
      error code: 401, desc: "Invalid secret"
      error code: 403, desc: "Token does not own this software"
      error code: 400, desc: "Missing or invalid arguments"
      def create
        unless update_authorized?(required_scope: WarpEngine::ApplicationToken::UPDATE_SCOPE)
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end

        %i[name platform version].each do |key|
          return render json: { error: "#{key.to_s.capitalize} not provided" }, status: :bad_request if params[key].blank?
        end

        unless software_ownership_authorized?(params[:name])
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        input = WarpEngine::PublishInputDto.new(
          platform: params[:platform],
          name:     params[:name],
          version:  params[:version]
        )

        WarpEngine::PublishService.new.publish(input)
        claim_software_ownership(params[:name])

        render json: { published: true, name: params[:name], platform: params[:platform], version: params[:version] }
      end
    end
  end
end
