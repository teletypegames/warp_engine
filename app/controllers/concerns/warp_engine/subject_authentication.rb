module WarpEngine
  # Who the caller is, on the read-only side of the API.
  #
  # Distinct from UpdateAuthentication, which guards publishing: that one asks "may this
  # pipeline write to the catalog", this one asks "whose library am I looking at". The
  # answer is allowed to be nobody — an anonymous caller is a normal, supported caller,
  # and a catalog with no policy configured never needs one.
  #
  # The credential is a bearer token, because that is what a client can carry: it has no
  # cookie jar and no browser session.
  module SubjectAuthentication
    extend ActiveSupport::Concern

    private

    # The ApplicationToken behind the request, or nil.
    def current_access_token
      return @current_access_token if defined?(@current_access_token)

      @current_access_token = resolve_access_token
    end

    # Whoever that token belongs to — the host's own object. nil when the request is
    # anonymous, when the token is unknown, or when no subject class is configured.
    def current_subject
      current_access_token&.owner
    end

    def resolve_access_token
      return nil unless WarpEngine.identity_configured?

      token = bearer_token
      return nil if token.blank?

      record = WarpEngine::ApplicationToken.authenticate(
        token, required_scope: WarpEngine::ApplicationToken::CATALOG_SCOPE
      )
      return nil if record.nil?

      record.touch_last_used!
      record
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      return nil unless header.start_with?("Bearer ")

      header.delete_prefix("Bearer ").strip.presence
    end
  end
end
