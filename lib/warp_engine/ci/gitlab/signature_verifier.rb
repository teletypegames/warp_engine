module WarpEngine
  module CI
    module Gitlab
      class SignatureVerifier
        def initialize(request, webhook_secret:)
          @request        = request
          @webhook_secret = webhook_secret
        end

        def valid?
          token = @request.headers["X-Gitlab-Token"]
          return false if token.blank? || @webhook_secret.blank?

          ActiveSupport::SecurityUtils.secure_compare(token, @webhook_secret)
        end
      end
    end
  end
end
