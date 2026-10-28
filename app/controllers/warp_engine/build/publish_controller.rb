module WarpEngine
  module Build
    # Registers uploaded build artifacts as a release. Needs the update
    # credential in <tt>X-Update-Secret</tt> (see WarpEngine::UpdateAuthentication).
    class PublishController < ApiController
      include UpdateAuthentication

      resource_description do
        short "Build release publishing"
      end

      api :POST, "/build/publish", "Register an uploaded build as a release"
      header "X-Update-Secret", "Shared secret or application token (update scope)", required: true
      param :name, String, required: true, desc: "Software name"
      param :platform, String, required: true, desc: "Platform (one of WarpEngine::Platform.names)"
      param :version, String, required: true, desc: "Version string"
      returns code: 200, desc: "JSON with the published name/platform/version"
      error code: 401, desc: "Invalid secret"
      error code: 403, desc: "Token does not own this software"
      error code: 400, desc: "Missing or invalid arguments"
      error code: 422, desc: "A kind the platform requires was not uploaded"
      error code: 409, desc: "A newer version is published already"
      # <tt>POST /build/publish</tt>.
      #
      # [name]     the software name
      # [platform] one of WarpEngine::Platform.names
      # [version]  the version string
      #
      # Validates the input (WarpEngine::PublishInputDto), publishes through
      # WarpEngine::PublishService (creating or updating the software, its release
      # and release assets) and gives an unowned software to the token's owner.
      # Renders <tt>{ "published": true, "name", "platform", "version" }</tt>.
      # Responds 401 without a valid credential, 400 for invalid input, 403 when
      # the token does not own the software, 422 with +missing+ kinds when a
      # required asset was not uploaded, and 409 when a newer version is published.
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
      rescue WarpEngine::Platforms::MissingAssetsError => e
        render json: { error: e.message, missing: e.kinds }, status: :unprocessable_content
      rescue WarpEngine::PublishService::StaleVersionError => e
        render json: { error: e.message }, status: :conflict
      end
    end
  end
end
