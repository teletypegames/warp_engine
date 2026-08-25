module WarpEngine
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
