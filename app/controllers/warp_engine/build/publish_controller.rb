module WarpEngine
  module Build
    # Registers uploaded build artifacts as a release. Needs the update
    # credential in <tt>X-Update-Secret</tt> (see WarpEngine::UpdateAuthentication).
    class PublishController < ApiController
      include UpdateAuthentication

      # The scopes that may publish: the CI's and another engine's.
      PUBLISH_SCOPES = [ WarpEngine::ApplicationToken::UPDATE_SCOPE, WarpEngine::ApplicationToken::SYNC_SCOPE ].freeze

      resource_description do
        short "Build release publishing"
      end

      api :POST, "/build/publish", "Register an uploaded build as a release"
      header "X-Update-Secret", "Shared secret or application token (update or sync scope)", required: true
      param :name, String, required: true, desc: "Software name"
      param :platform, String, required: true, desc: "Platform (one of WarpEngine::Platform.names)"
      param :version, String, required: true, desc: "Version string"
      param :commit, String, required: false, desc: "The commit the CI built (hex)"
      param :app, String, required: false, desc: "The platform variant (cli, gui) of a platform with variants; blank: the default one"
      param :disable, String, required: false, desc: "The kinds the software turns off (the CI marker's disable: key), separated by commas; web turns off the web play"
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
      # [commit]   the commit the CI built, stored on the release (optional)
      # [app]      the platform variant, stored on the software (optional)
      # [disable]  the kinds the software turns off, stored on it as its
      #            WarpEngine::Software#disabled_kinds (optional; absent
      #            leaves them as they are)
      #
      # Validates the input (WarpEngine::PublishInputDto), publishes through
      # WarpEngine::PublishService (creating or updating the software, its release
      # and release assets) and gives an unowned software to the token's owner.
      # A token with the +sync+ scope (a WarpEngine::SyncPeer) must pass
      # WarpEngine::SyncInboundService (403 when inbound sync or the peer is
      # off or the lists refuse, 409 when +protect_local+ keeps a version the
      # CI published here); it publishes with origin +sync+, so the release is
      # not pushed on, and the outcome is logged as an inbound
      # WarpEngine::SyncEvent.
      # Renders <tt>{ "published": true, "name", "platform", "version" }</tt>.
      # Responds 401 without a valid credential, 400 for invalid input, 403 when
      # the token does not own the software, 422 with +missing+ kinds when a
      # required asset was not uploaded, and 409 when a newer version is published.
      def create
        unless update_authorized?(required_scope: PUBLISH_SCOPES)
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end

        input = WarpEngine::PublishInputDto.new(
          platform: params[:platform],
          name:     params[:name],
          version:  params[:version],
          commit:   params[:commit].presence,
          app:      params[:app].presence,
          disable:  params[:disable]
        )
        return render json: { error: input.error_message }, status: :bad_request unless input.valid?

        unless software_ownership_authorized?(input.name)
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        if sync_request? && (refusal = inbound.refuse_publish(token: current_application_token, input: input))
          log_inbound(input, status: refusal.status, message: refusal.message)
          return render json: { error: refusal.message }, status: refusal.status
        end

        release = WarpEngine::PublishService.new.publish(input, source: sync_request? ? :sync : :ci,
                                                                peer: sync_request? ? inbound.peer_of(current_application_token) : nil)
        claim_software_ownership(input.name)
        log_inbound(input, release: release, status: 200)

        render json: { published: true, name: input.name, platform: input.platform, version: input.version }
      rescue WarpEngine::Platforms::MissingAssetsError => e
        log_inbound(input, status: 422, message: e.message)
        render json: { error: e.message, missing: e.kinds }, status: :unprocessable_content
      rescue WarpEngine::PublishService::StaleVersionError => e
        log_inbound(input, status: 409, message: e.message)
        render json: { error: e.message }, status: :conflict
      end

      private

      def inbound = @inbound ||= WarpEngine::SyncInboundService.new

      def log_inbound(input, status:, release: nil, message: nil)
        return unless sync_request?

        WarpEngine::SyncService.new.record_inbound(name: input.name, platform: input.platform, version: input.version,
                                                   release: release, http_status: status, message: message,
                                                   token: current_application_token,
                                                   peer: inbound.peer_of(current_application_token))
      end
    end
  end
end
