module WarpEngine
  module AdminApi
    class Error < StandardError
      attr_reader :status, :details, :headers

      def self.not_found = new(404, "Not found")
      def self.unauthorized = new(401, "Unauthorized", headers: { "WWW-Authenticate" => %(Bearer realm="warp_engine") })
      def self.forbidden(message = "Forbidden") = new(403, message)
      def self.bad_request(message) = new(400, message)
      def self.conflict(message) = new(409, message)
      def self.read_only = new(405, "The Admin API is read-only here")

      def self.invalid(record)
        details = record.errors.to_hash.transform_keys { |key| key.to_s.camelize(:lower) }
        new(422, "Validation failed", details: details)
      end

      def initialize(status, message, details: nil, headers: {})
        super(message)
        @status  = status
        @details = details
        @headers = headers
      end

      def body
        { error: message, details: details }.compact
      end
    end

    class ConfigurationError < StandardError; end
  end
end
