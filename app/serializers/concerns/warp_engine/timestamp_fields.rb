module WarpEngine
  # Timestamp formatting constants shared by the catalog serializers, which
  # keep the timestamp shape of the original Go service.
  module TimestampFields
    # Rendered in place of a missing creation or update time: Go's zero
    # <tt>time.Time</tt>.
    GO_ZERO_TIME = "0001-01-01T00:00:00Z"
    # +strftime+ format of a rendered timestamp: UTC ISO 8601 with milliseconds.
    TS_FORMAT    = "%Y-%m-%dT%H:%M:%S.%3NZ"
  end
end
