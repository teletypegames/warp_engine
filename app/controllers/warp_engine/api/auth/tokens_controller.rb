module WarpEngine
  module Api
    module Auth
      # Revokes client bearer tokens (signing a client out).
      class TokensController < WarpEngine::ApiController
        resource_description do
          short "Client tokens"
        end

        api :DELETE, "/api/auth/token", "Revoke the bearer token this request carries"
        returns code: 204, desc: "Revoked"
        error code: 401, desc: "No usable bearer token on the request"
        # <tt>DELETE /api/auth/token</tt>.
        #
        # Revokes the catalog bearer token the request carries and responds 204, or
        # 401 when the request carries no usable token.
        def destroy
          token = current_access_token
          return head(:unauthorized) if token.nil?

          WarpEngine::DeviceGrantService.new.revoke(token: token)
          head :no_content
        end
      end
    end
  end
end
