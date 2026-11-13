module WarpEngine
  module AdminApi
    # An Admin API failure with the HTTP status it answers with. The controller and
    # Mcp render it as <tt>{ error:, details: }</tt> (see #body) with #headers set.
    class Error < WarpEngine::Error
      # The HTTP status code, the optional details hash (field name to messages) and
      # the extra response headers.
      attr_reader :status, :details, :headers

      # A 404 Not found.
      def self.not_found = new(404, "Not found")
      # A 401 Unauthorized with a Bearer <tt>WWW-Authenticate</tt> challenge.
      def self.unauthorized = new(401, "Unauthorized", headers: { "WWW-Authenticate" => %(Bearer realm="warp_engine") })
      # A 403 with +message+.
      def self.forbidden(message = "Forbidden") = new(403, message)
      # A 400 with +message+.
      def self.bad_request(message) = new(400, message)
      # A 409 with +message+.
      def self.conflict(message) = new(409, message)
      # A 405 for a write on a read-only Admin API (Configuration#read_only).
      def self.read_only = new(405, "The Admin API is read-only here")

      # A 422 Validation failed whose details are the validation errors of +record+,
      # keyed by lower camel case attribute names.
      def self.invalid(record)
        details = record.errors.to_hash.transform_keys { |key| key.to_s.camelize(:lower) }
        new(422, "Validation failed", details: details)
      end

      # [status]  the HTTP status code
      # [message] the error message
      # [details] an optional hash of further details
      # [headers] extra response headers
      def initialize(status, message, details: nil, headers: {})
        super(message)
        @status  = status
        @details = details
        @headers = headers
      end

      # The JSON body of the error: <tt>{ error:, details: }</tt> without a nil +details+.
      def body
        { error: message, details: details }.compact
      end
    end

    # Raised when the Admin API is configured in a way it cannot run, e.g. MCP without
    # the +mcp+ gem. The same class as WarpEngine::ConfigurationError.
    ConfigurationError = WarpEngine::ConfigurationError
  end
end
