module WarpEngine
  # Signing out: a client throws away its own token.
  #
  # Revocation is a soft delete on the ApplicationToken, so the record of which device
  # signed in and when survives it. The person's own list of devices — where somebody
  # revokes a token for a laptop they no longer have — is the host's page, because it
  # needs a session and a browser.
  class Api::Auth::TokensController < ApiController
    resource_description do
      short "Client tokens"
    end

    api :DELETE, "/api/auth/token", "Revoke the bearer token this request carries"
    returns code: 204, desc: "Revoked"
    error code: 401, desc: "No usable bearer token on the request"
    def destroy
      token = current_access_token
      return head(:unauthorized) if token.nil?

      WarpEngine::DeviceGrantService.new.revoke(token: token)
      head :no_content
    end
  end
end
