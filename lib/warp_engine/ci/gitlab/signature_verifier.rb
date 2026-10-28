module WarpEngine
  module CI
    module Gitlab
      # Checks that a GitLab config request carries the configured webhook secret.
      class SignatureVerifier
        # [request]        the incoming ActionDispatch::Request
        # [webhook_secret] the expected value of the <tt>X-Gitlab-Token</tt> header
        def initialize(request, webhook_secret:)
          @request        = request
          @webhook_secret = webhook_secret
        end

        # Returns +true+ when the <tt>X-Gitlab-Token</tt> header equals the webhook
        # secret (constant-time comparison); +false+ when either is blank or they differ.
        def valid?
          token = @request.headers["X-Gitlab-Token"]
          return false if token.blank? || @webhook_secret.blank?

          ActiveSupport::SecurityUtils.secure_compare(token, @webhook_secret)
        end
      end
    end
  end
end
