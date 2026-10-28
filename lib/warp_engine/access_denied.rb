module WarpEngine
  # Raised when the access policy refuses a download, or when the policy itself
  # fails while deciding (a crashing policy counts as a refusal).
  class AccessDenied < StandardError; end
end
