module WarpEngine
  # The base class of every error the engine raises on purpose. A host can
  # rescue it to catch them all; each part of the engine raises a subclass.
  class Error < StandardError; end

  # A host configuration the engine cannot run with: a directory, a feed, a
  # platform or the Admin API set up wrongly. WarpEngine::Feeds.validate!
  # raises it at boot.
  class ConfigurationError < Error; end

  # Raised when the access policy denies a download or a file; the API
  # controllers render it as 403.
  #
  # These three are shared by every part of the engine; an error that belongs
  # to one part lives beside it (WarpEngine::PublishService::StaleVersionError,
  # WarpEngine::Platforms::MissingAssetsError, WarpEngine::CI::Error,
  # WarpEngine::AdminApi::Error).
  class AccessDenied < Error; end
end
