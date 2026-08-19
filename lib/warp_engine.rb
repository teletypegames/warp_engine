# Az engine ActiveJob-ra épülő jobot szállít (PipelineSyncJob), ezért a
# framework betöltése a mi dolgunk: a host application.rb-je nem feltétlenül
# require-öli az active_job/railtie-t, és eager loadnál (production) a
# WarpEngine::ApplicationJob különben uninitialized constant-tal elszáll.
require "active_job/railtie"

require "blueprinter"
require "apipie-rails"

require "warp_engine/version"
require "warp_engine/configuration"
require "warp_engine/storage"
require "warp_engine/access"

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

  # A host innen tudja, hogy a publikálás ActiveSupport::Notifications-t szór
  # ("warp_engine.publish"), és nem kell modell-callbackre kapaszkodnia.
  # Régebbi engine-verziókon a metódus nem létezik, ezért a hívó oldalon
  # respond_to?-val kérdezendő.
  def self.instruments_publish?
    true
  end

  def self.storage
    Storage.adapter
  end

  # Who may see and download what. :open by default — see WarpEngine::AccessPolicy.
  def self.access_policy
    AccessPolicy.current
  end

  # The host has configured a subject class, so client sign-in is available. A client
  # asks GET /api/service rather than this, but the engine's own controllers need it.
  def self.identity_configured?
    config.access_token_owner_class.present?
  end
end

require "warp_engine/engine"
