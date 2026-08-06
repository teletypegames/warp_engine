require "blueprinter"
require "apipie-rails"

require "warp_engine/version"
require "warp_engine/configuration"

module WarpEngine
  # A tábláink prefix nélküliek (softwares, releases, ...) — az isolate_namespace
  # által generált "warp_engine_" prefixet üresre cseréljük. Az engine.rb require-je
  # előtt kell definiálva lennie.
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
end

require "warp_engine/engine"
