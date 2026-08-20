require "active_job/railtie"

require "blueprinter"
require "apipie-rails"

require "warp_engine/version"
require "warp_engine/configuration"
require "warp_engine/storage"
require "warp_engine/access"

module WarpEngine

  def self.table_name_prefix
    ""
  end

  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield(config)
  end

  def self.woodpecker_configured?
    config.woodpecker_url.present? && config.woodpecker_api_token.present?
  end

  def self.instruments_publish?
    true
  end

  def self.storage
    Storage.adapter
  end

  def self.access_policy
    AccessPolicy.current
  end

  def self.identity_configured?
    config.access_token_owner_class.present?
  end
end

require "warp_engine/engine"
