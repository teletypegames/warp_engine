require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_dispatch/railtie"

Bundler.require(*Rails.groups)
require "warp_engine"

module HostApp
  class Application < Rails::Application
    config.load_defaults 8.0

    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Demo stack: reachable as localhost, gitea-network hostnames, etc.
    config.hosts.clear
  end
end
