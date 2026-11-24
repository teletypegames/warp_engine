module WarpEngine
  module Build
    # Removes here what another engine pushed by sync, when it removed it
    # there (WarpEngine::Sync::Transports::Http#deliver_removal). Needs a
    # token with the +sync+ scope in <tt>X-Update-Secret</tt> (see
    # WarpEngine::UpdateAuthentication).
    class RemovalsController < ApiController
      include UpdateAuthentication

      resource_description do
        short "Removals from sync"
      end

      api :DELETE, "/build/release", "Remove a release, or a whole software, this engine's peer pushed here"
      header "X-Update-Secret", "Sync token", required: true
      param :name, String, required: true, desc: "Software name"
      param :version, String, required: false, desc: "Release version; without it every release the peer pushed, and the software"
      returns code: 200, desc: %(JSON {"removed": [version, ...], "software": true|false})
      error code: 401, desc: "Invalid token"
      error code: 403, desc: "Sync inbound is off, or the token's peer may not push here"
      error code: 404, desc: "No such software or version here"
      error code: 409, desc: "Not pushed here by this peer (published here, or by another peer)"
      # <tt>DELETE /build/release</tt>.
      #
      # [name]    the software name
      # [version] the release version, or none for the software
      #
      # Checks the peer through WarpEngine::SyncInboundService#refuse_removal,
      # removes through WarpEngine::SyncInboundService#remove and logs an
      # inbound WarpEngine::SyncEvent (step +remove+). Renders
      # <tt>{ "removed": [...], "software": ... }</tt>; 400 without a name,
      # and 401, 403, 404 and 409 as listed.
      def destroy
        unless update_authorized?(required_scope: [ WarpEngine::ApplicationToken::SYNC_SCOPE ])
          return render(json: { error: "Unauthorized" }, status: :unauthorized)
        end

        name = params[:name].to_s
        return render(json: { error: "name is required" }, status: :bad_request) if name.blank?

        service = WarpEngine::SyncInboundService.new
        if (refusal = service.refuse_removal(token: current_application_token))
          log(name, nil, refusal.status, refusal.message)
          return render(json: { error: refusal.message }, status: refusal.status)
        end

        peer = service.peer_of(current_application_token)
        removal = service.remove(peer: peer, name: name, version: params[:version].presence)
        log(name, peer, removal.status, removal.message)
        if removal.status == 200
          render json: { removed: removal.versions, software: removal.software }
        else
          render json: { error: removal.message }, status: removal.status
        end
      end

      private

      def log(name, peer, status, message)
        WarpEngine::SyncEvent.log(direction: "inbound", status: status == 200 ? "succeeded" : "skipped", sync_peer: peer,
                                  software_id: WarpEngine::Software.where(name: name).pick(:id), software_name: name,
                                  version: params[:version].presence, step: "remove", http_status: status, message: message,
                                  token_prefix: current_application_token&.token_prefix)
      end
    end
  end
end
