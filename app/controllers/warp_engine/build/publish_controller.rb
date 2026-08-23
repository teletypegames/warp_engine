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
      param :platform, String, required: true, desc: "Platform (one of WarpEngine::Platform::NAMES)"
      param :version, String, required: true, desc: "Version string"
      returns code: 200, desc: "JSON with the published name/platform/version"
      error code: 401, desc: "Invalid secret"
      error code: 403, desc: "Token does not own this software"
      error code: 400, desc: "Missing or invalid arguments"
      def create
        unless update_authorized?(required_scope: WarpEngine::ApplicationToken::UPDATE_SCOPE)
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end

        input = WarpEngine::PublishInputDto.new(
          platform: params[:platform],
          name:     params[:name],
          version:  params[:version]
        )
        return render json: { error: input.error_message }, status: :bad_request unless input.valid?

        unless software_ownership_authorized?(input.name)
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        WarpEngine::PublishService.new.publish(input)
        claim_software_ownership(input.name)

        render json: { published: true, name: input.name, platform: input.platform, version: input.version }
      end
    end
  end
end
