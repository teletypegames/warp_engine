require "active_job/railtie"

require "blueprinter"
require "apipie-rails"

require "warp_engine/version"
require "warp_engine/configuration"
require "warp_engine/platform"
require "warp_engine/storage"
require "warp_engine/access"
require "warp_engine/access_denied"
require "warp_engine/images"
require "warp_engine/ci"
require "warp_engine/additional_resource"
require "warp_engine/shelves"
require "warp_engine/admin_api"

# WarpEngine is the mountable Rails engine behind a game catalog: it ingests CI
# builds of software titles, stores their releases and assets, and serves them
# through the catalog API, the admin API and the ActiveAdmin screens.
#
# The host configures it once in an initializer:
#
#   WarpEngine.configure do
#     file_container_path Rails.root.join("storage/files")
#     site_url "https://games.example.org"
#   end
#
# The pluggable parts (storage, images, CI, access policy) are reached through
# the module accessors below; each falls back to the engine's default adapter.
module WarpEngine
  # Returns the table name prefix for the engine's models: the empty string,
  # so the engine's tables carry no +warp_engine_+ prefix.
  def self.table_name_prefix
    ""
  end

  # Returns the process-wide WarpEngine::Configuration, creating it with its
  # defaults on first use.
  def self.config
    @config ||= Configuration.new
  end

  # Configures the engine. A block without arguments is evaluated with the
  # WarpEngine::Configuration::DSL; a block taking one argument is yielded the
  # WarpEngine::Configuration itself:
  #
  #   WarpEngine.configure { site_url "https://games.example.org" }
  #   WarpEngine.configure { |config| config.file_container_path = "/srv/files" }
  #
  # Returns the result of the block.
  def self.configure(&block)
    block.arity.zero? ? Configuration::DSL.apply(config, &block) : yield(config)
  end

  # Returns +true+: the engine emits the <tt>warp_engine.publish</tt>
  # ActiveSupport notification whenever a release is published, so hosts may
  # subscribe to it.
  def self.instruments_publish?
    true
  end

  # Returns the configured storage adapter (see WarpEngine::Storage.adapter).
  def self.storage
    Storage.adapter
  end

  # Returns the configured image adapter (see WarpEngine::Images.adapter).
  def self.images
    Images.adapter
  end

  # Returns the configured CI adapter (see WarpEngine::CI.adapter).
  def self.ci
    CI.adapter
  end

  # Returns the configured access policy (see WarpEngine::AccessPolicy.current).
  def self.access_policy
    AccessPolicy.current
  end

  # Returns +true+ when the host configured an +access_token_owner_class+, which
  # enables client sign-in and subject authentication.
  def self.identity_configured?
    config.access_token_owner_class.present?
  end
end

require "warp_engine/engine"
