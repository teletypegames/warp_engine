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

    # Whoever the request is on behalf of — the host's own object, or nil.
    #
    # Two ways to be somebody, tried in that order. A bearer token is what a client
    # carries. A *browser* carries a session instead, and the engine has no idea what a
    # session is here — so a host that wants its signed-in visitors recognised on these
    # endpoints supplies a resolver:
    #
    #   c.subject_resolver = ->(request) { request.env["warden"]&.user }
    #
    # Without one, a browser is simply anonymous, which is what it always was.
    def current_subject
      return @current_subject if defined?(@current_subject)

      @current_subject = current_access_token&.owner || resolve_host_subject
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

    # A resolver that raises must not take the request with it: it runs on every read
    # endpoint, and a broken one would turn the whole API into 500s rather than into
    # anonymous requests, which is the honest fallback.
    def resolve_host_subject
      resolver = WarpEngine.config.subject_resolver
      return nil if resolver.nil?

      resolver.call(request)
    rescue StandardError => e
      Rails.logger.error("[WarpEngine::SubjectAuthentication] subject_resolver #{e.class}: #{e.message}")
      nil
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      return nil unless header.start_with?("Bearer ")

      header.delete_prefix("Bearer ").strip.presence
    end
  end
end
